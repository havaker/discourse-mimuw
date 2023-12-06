import requests
import requests_unixsocket
import argparse
import os
import json
import logging
import urllib.parse

# When modeling the Discourse entities (such as groups or categories), we can express
# their desired configuration in Nix. Given that, we need a way to apply that configuration
# to the Discourse instance. This is what this script is for.
#
# More specifically, the description of Discourse entities expressed in Nix can
# be translated into JSON, which can be understood by this script. The script
# queries the Discourse API to find out what entities already exist, which ones
# need to be created and which ones need to be updated. It then performs the
# API calls to apply the desired configuration.


# Consider the following Nix expression:
# groups = {
#   admins = {
#     full_name = "Admins";
#     usernames = [ "balenciaga" ];
#   };
# }
# It is temping to use the name expressed by the attribute name of `group.admins` as
# the name of the group in Discourse. This leads to some limitations, however - for
# example the name cannot be changed without deleting the group and creating a new one.
# This may be undesirable, because the group may have some members already (a
# state which is not expressed in Nix). To solve this, a different Nix schema is
# used, where the attribute names are used as identifiers, but the names of the
# groups are expressed in the group's `name` attribute:
# groups = {
#   admins = { # This is the Nix-side identifier of the group
#     name = "admins"; # This is the name of the group
#     full_name = "Admins";
#     usernames = [ "balenciaga" ];
#   };
# }
# Having such a schema, it is now possible to change the name of the group without
# deleting it. For example, the following Nix expression will rename the group:
# groups = {
#   admins = { # Nix-side identifier of the group (must be the same as before)
#     name = "admins2137"; # Changed name of the group
#     full_name = "Admins";
#     usernames = [ "balenciaga" ];
#   };
# }
# In the above case, the script has to find out that the group with the name `admins`
# was renamed to `admins2137`. To do that, it stores the mapping between the Nix-side
# identifiers and the Discourse-side identifiers in a persistent store.
# Each time the script is run, it will load the store, compare the Nix-side identifiers
# with the ones in the store and if they differ, it will assume that the group
# was renamed. This is this store class:
class AttributeNameToIdStore:

    def __init__(self, path):
        logging.debug(f'Loading attribute to id mappings from {path}')
        self.path = path

        try:
            with open(path, 'r') as f:
                self.data = json.load(f)
        except FileNotFoundError:
            logging.info(
                f'Attribute to id mappings file {path} not found, creating a new one'
            )
            self.data = {"groups": {}}

            # Check if the data directory exists.
            if not os.path.exists(os.path.dirname(path)):
                raise Exception(
                    f'Data directory {os.path.dirname(path)} does not exist')

    def save(self, with_config=None):
        logging.debug(f'Saving attribute to id mappings to {self.path}')
        if with_config is not None:
            # Add the config to the store file, for testing/debugging purposes.
            self.data["config"] = with_config
        with open(self.path, 'w') as f:
            json.dump(self.data, f)

    def get_group_id(self, nix_attr_name, api_fallback):
        gid = self.data['groups'].get(nix_attr_name)
        if gid is None:
            logging.debug(
                f'Nix attribute `services.discourse.groups.{nix_attr_name}`'
                'had no corresponding discourse group id in the store file,'
                ' using API fallback to find it')
            gid = api_fallback()
            self.set_group_id(nix_attr_name, gid)
        return gid

    def set_group_id(self, nix_attr_name, gid):
        if gid is not None:
            self.data["groups"][nix_attr_name] = gid


# REST API client for Discourse.
# FIXME: Pagination is not supported.
class DiscourseClient:

    def __init__(self, url, token):
        self.headers = {'Api-Key': token, 'Api-Username': 'system'}
        self.url = url

    def _request(self, method, path, data=None):
        url = f"{self.url}/{path}"
        res = requests.request(method, url, headers=self.headers, json=data)
        res.raise_for_status()
        # Discourse API returns 200 in every successful case
        if res.status_code != 200:
            raise Exception(
                f'API request failed with status code {res.status_code} and body {res.text}'
            )
        return res.json()

    def find_group_id_by_name(self, name):
        res = self._request('GET', 'groups.json')
        for group in res['groups']:
            if group['name'] == name:
                gid = group['id']
                logging.debug(
                    f'Found group with name \'{name}\' and id = {gid} using the API'
                )
                return gid
        logging.debug(f'No group with name \'{name}\' was found using the API')
        return None

    def get_group_members(self, group_name):
        res = self._request('GET', f'groups/{group_name}/members.json')
        return res['members']

    def create_group(self, definition):
        # https://docs.discourse.org/#tag/Groups/operation/createGroup
        data = {'group': definition}
        res = self._request('POST', 'admin/groups.json', data=data)
        gid = res['basic_group']['id']
        logging.debug(
            f'Created group with name \'{definition["name"]}\' and id = {gid} using the API'
        )
        return gid

    def update_group(self, group_id, definition):
        # https://docs.discourse.org/#tag/Groups/operation/updateGroup
        data = {'group': definition}

        self._request('PUT', f'groups/{group_id}.json', data=data)
        logging.debug(
            f'Updated group {definition["name"]} with id = {group_id} using the API'
        )


# The business logic of the applier.
# Expects to be given a path to a JSON config file, which describes the desired
# Discourse entities. The config file is expected to have the following structure:
# {
#   "groups": {
#     # Nix-side identifier of the group may be any string.
#     # There may be any number of groups such as the one below.
#     "@nix-side-identifier": {
#        # Attributes of the group, as described in the Discourse API docs
#      }
#   }
# }
class Configurator:

    def __init__(self, client, config, data_dir):
        self.client = client

        with open(config, 'r') as f:
            self.config = json.load(f)

        data_path = os.path.join(data_dir, 'nix_to_discourse_ids.json')
        self.store = AttributeNameToIdStore(data_path)

    # Apply the desired configuration of a single group.
    # If the group does not exist, it will be created.
    # If the group exists, but its name differs from the one in the config,
    # it will be updated.
    def apply_group(self, group_attr_name, definition):
        api_fallback = lambda: self.client.find_group_id_by_name(definition[
            'name'])
        discourse_group_id = self.store.get_group_id(group_attr_name,
                                                     api_fallback)

        if discourse_group_id is None:
            logging.debug(
                f'Nix attribute `services.discourse.groups.{group_attr_name}` had no corresponding discourse group'
            )
            discourse_group_id = self.client.create_group(definition)
            self.store.set_group_id(group_attr_name, discourse_group_id)
        else:
            logging.debug(
                f'Nix attribute `services.discourse.groups.{group_attr_name}` was mapped to discourse group of id = {discourse_group_id}`'
            )
            self.client.update_group(discourse_group_id, definition)

    # TODO: Implement deletion of groups that are not present in the config
    def apply(self):
        for group_attr_name, definition in self.config["groups"].items():
            self.apply_group(group_attr_name, definition)
        self.store.save(with_config=self.config)


class ArgumentProvider:

    def __init__(self, default_loglevel='info'):
        self.parser = argparse.ArgumentParser()
        self.parser.add_argument(
            '--loglevel',
            default=default_loglevel,
            help=
            'Provide logging level. Possible values: debug, info, warning, error, critical'
        )

    def add_url_related_options(self):
        self.parser.add_argument('url', help='URL of the discourse instance')
        self.parser.add_argument(
            '--unix-socket',
            help='UNIX domain socket path, which'
            ' should be used instead of the standard TCP transport',
            default=None)

    def add_config_related_options(self):
        self.parser.add_argument('config', help='Path to the config file')
        self.parser.add_argument('data_dir', help='Path to the data directory')

    def add_user_with_group(self):
        self.parser.add_argument('user', help='Discourse username')
        self.parser.add_argument('group', help='Discourse group name')

    def parse_args(self):
        args = self.parser.parse_args()

        # Discourse API is always available to access from the local machine
        # through a UNIX socket on which Unicorn listens.
        # This option used the production and test environments. In the development
        # environment it is useful to run applier on another machine, so that the
        # applier can be run independently from the Discourse instance virtual machine.
        if hasattr(args, 'url') and args.unix_socket:
            # Allow using UNIX sockets in the requests package
            requests_unixsocket.monkeypatch()

            escaped_path = urllib.parse.quote_plus(args.unix_socket)
            args.url = f'http+unix://{escaped_path}'

        logging.basicConfig(level=args.loglevel.upper())
        # Do it before loading the token from the environment
        logging.info(
            f'The applier started with the following arguments: {args}')

        args.token = os.environ['DISCOURSE_API_KEY']
        if hasattr(args, 'url') and args.token is None:
            raise Exception(
                'DISCOURSE_API_KEY environment variable is not set')

        return args


# `applier` entry point (defined in the setup.py).
def apply():
    provider = ArgumentProvider()
    provider.add_url_related_options()
    provider.add_config_related_options()
    args = provider.parse_args()

    client = DiscourseClient(args.url, args.token)
    configurator = Configurator(client, args.config, args.data_dir)
    configurator.apply()

    logging.info('Applied the configuration successfully')


# entry point used by the test suite
def assert_user_in_group():
    provider = ArgumentProvider()
    provider.add_url_related_options()
    provider.add_user_with_group()
    args = provider.parse_args()

    client = DiscourseClient(args.url, args.token)

    if client.find_group_id_by_name(args.group) is None:
        raise Exception(f'Group with name {args.group} does not exist')
    members = client.get_group_members(args.group)
    assert args.user in [member["username"] for member in members]
