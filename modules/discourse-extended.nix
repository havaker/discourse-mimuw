{ config, lib, pkgs, ... }: with lib; let
  cfg = config.services.discourse;
in
{
  options = {
    # This module provides a way to configure Discourse groups using Nix
    # It's an alternative solution to configuring entities such as groups
    # using the admin panel UI in Discourse.
    # The main advantage of this approach is that it allows to have a single
    # source of truth for the configuration of Discourse, that can be version
    # controlled, reviewed and tested.
    services.discourse.groups = mkOption {
      type = types.attrsOf (types.submodule (args: {
        options = {
          name = mkOption {
            type = types.str;
            description = "The name of the group.";
          };
          full_name = mkOption {
            type = types.str;
            description = "Full name of the group.";
          };
          bio_raw = mkOption {
            type = types.str;
            default = "";
            description = "About the group.";
          };
          usernames = mkOption {
            type = with types; nullOr (listOf str);
            default = null;
            description = "The usernames of the group.";
          };
          owner_usernames = mkOption {
            type = with types; nullOr (listOf str);
            default = null;
            description = "The owner usernames of the group.";
          };
          automatic_membership_email_domains = mkOption {
            type = types.listOf types.str;
            description = "The automatic membership email domains of the group.";
          };
          visibility_level = mkOption {
            type = types.enum [
              "public"
              "logged_on_users"
              "members"
              "staff"
              "owners"
            ];
            description = "The visibility level of the group.";
          };
          primary_group = mkOption {
            type = types.bool;
            default = false;
            description = "Whether the group is the primary group.";
          };
          public_admission = mkOption {
            type = types.bool;
            default = false;
            description = "Allow users to join this group freely (requires publicly visible group).";
          };
          public_exit = mkOption {
            type = types.bool;
            default = false;
            description = "Allow users to leave the group freely.";
          };
          default_notification_level = mkOption {
            type = types.enum [
              "muted"
              "regular"
              "tracking"
              "watching"
              "watching_first_post"
            ];
            default = "regular";
            description = "The default notification level of the group.";
          };
        };
      }));

      default = { };
    };
  };

  # This is an implementation part of this module.
  # Summary of what is done here:
  # 1. Convert the `config.services.discourse.groups` value defined by the user
  # of this module (flakes.nix) to the format that is easier to push into the
  # Discourse API.
  # 2. Setup the `applier` (defined as a package in flake.nix) so that it runs
  # after Discourse is started to apply the desired group configuration.
  config =
    let
      # Convert visibility level expressed as a string to an integer.
      # public: 0, logged_on_users: 1, members: 2, staff: 3, owners: 4
      visibility = level:
        let
          order = [ "public" "logged_on_users" "members" "staff" "owners" ];
        in
        lists.findFirstIndex (x: x == level) null order;
      # Convert notification level expressed as a string to an integer.
      # muted: 0, regular: 1, tracking: 2, watching: 3, watching_first_post: 4
      notification = level:
        let
          order = [ "muted" "regular" "tracking" "watching" "watching_first_post" ];
        in
        lists.findFirstIndex (x: x == level) null order;
      # Concatenate a list of strings into a single string separated by a
      # separator and set the result as an attribute (if not null).
      optionalConcated = attr: values: separator:
        if values != null then { "${attr}" = concatStringsSep separator values; } else { };
      # Given a group specification with a format defined in the `options` of
      # this module, convert it to one that Discourse uses in its API (and the
      # `applier` can understand).
      groupToApiFormat = group:
        let
          base = {
            inherit (group) name full_name bio_raw primary_group public_admission public_exit;
            visibility_level = visibility group.visibility_level;
            default_notification_level = notification group.default_notification_level;
          };
          # Attribute sets that may be empty and will be merged into base.
          # Merging attribute sets with // was chosen because it allows to
          # define an attribute conditionally.
          # Format used by those attributes can be seen here: https://docs.discourse.org/#tag/Groups/operation/createGroup
          usernames = optionalConcated "usernames" group.usernames ",";
          owner_usernames = optionalConcated "owner_usernames" group.owner_usernames ",";
          automatic_membership_email_domains = optionalConcated "automatic_membership_email_domains" group.automatic_membership_email_domains "|";
        in
        base // usernames // owner_usernames // automatic_membership_email_domains;
      # Aggregated set of all groups defined by the user of this module.
      groupsSpecificationInApiFormat = mapAttrs (_: groupSpecification: groupToApiFormat groupSpecification) cfg.groups;
      # `applier` expects a JSON file with the following format:
      configInApiFormat = {
        groups = groupsSpecificationInApiFormat;
      };
      configFile = builtins.toFile "desired.json" (builtins.toJSON configInApiFormat);
      # Helper script to wait for Discourse to start.
      waitForDiscourse = pkgs.writeScriptBin "wait-for-discourse" ''
        timeout=$1
        start_time=$(date +%s)

        echo "Waiting for Discourse to start..."
        while [ ! -S /run/discourse/sockets/unicorn.sock ]; do
          current_time=$(date +%s)
          elapsed_time=$((current_time - start_time))

          if [ $elapsed_time -ge $timeout ]; then
            echo "Timeout: Discourse did not start within $timeout seconds."
            exit 1
          fi

          sleep 1;
        done
      '';
    in
    mkIf cfg.enable {
      # Easiest way to run the `applier` is to add it as a `postStart` of the
      # original Discourse service.
      systemd.services.discourse = {
        serviceConfig.StateDirectory = [ "discourse/api" ];

        postStart = ''
          set -o errexit -o pipefail -o nounset -o errtrace
          shopt -s inherit_errexit

          cat ${configFile}

          if [[ ! -e /var/lib/discourse/api/key ]]; then
            echo "Creating master API key..."
            discourse-rake api_key:create_master[system] >/var/lib/discourse/api/key
          fi

          # `applier` expects the API key to be set as an environment variable.
          DISCOURSE_API_KEY=$(<'/var/lib/discourse/api/key')
          export DISCOURSE_API_KEY
          echo "Loaded master API key."

          ${waitForDiscourse}/bin/wait-for-discourse 60
          ${pkgs.applier}/bin/applier http://localhost ${configFile} /var/lib/discourse/api --unix-socket /run/discourse/sockets/unicorn.sock --loglevel debug
        '';
      };
    };
}
