# See https://nixos.org/manual/nixos/stable/#ssec-machine-objects for
# documentation of methods available on `server` and `client` objects.

start_all()

# Since the addition of `applier` module, the Discourse service signals to
# SystemD that it started after when it actually started, so there is no need
# to wait for the Unicorn socket file to be created.
server.wait_for_unit("discourse.service")

# Get the API key for interacting with Discourse.
api_key = server.succeed("cat /var/lib/discourse/api/key")
api_key = api_key[:-1] # Remove the trailing newline.

# Verify that the admin user is able to log in.
# `verify-login` is a script provided by the `selenium-scenarios` package.
client.succeed(
    "verify-login"
    " --address http://server"
    " --username \"$USERNAME\""
    " --headless"
)

# Verify it is possible to register a new user with a email address from
# the trusted students.mimuw.edu.pl domain.
# `registration` is a script provided by the `selenium-scenarios` package.
client.succeed(
    "registration"
    " --address http://server"
    " --mailhog-address http://server:8025"
    " --name \"Duży Pudzian\""
    " --username pudzian5"
    " --email duzypudzian5@students.mimuw.edu.pl"
    " --headless"
)

# Verify that the newly registered user is in the students group.
# `user-in-group` is a script provided by the `applier` package.
client.succeed(
    f"env DISCOURSE_API_KEY='{api_key}'"
    " user-in-group http://server pudzian5 students"
)

# Change the group configuration (group name: students -> studenciaki).
# Leveraging the fact that `applier` saves the current configuration as an
# attribute in its store, we can use `jq` to extract it, change it and save it
# for later use as an configuration input to `applier`.
server.succeed(
    "jq '.config | .groups.students.name = \"studenciaki\"' /var/lib/discourse/api/nix_to_discourse_ids.json > /changed.json"
)
server.succeed(
    f"env DISCOURSE_API_KEY='{api_key}'"
    " applier http://server /changed.json /var/lib/discourse/api"
)

# Validate that the group configuration has changed.
client.succeed(
    f"env DISCOURSE_API_KEY='{api_key}'"
    " user-in-group http://server pudzian5 studenciaki"
)

# Given a user with a non-student email address, registration should fail.
status, output = client.execute(
    "registration"
    " --address http://server"
    " --mailhog-address http://server:8025"
    " --name \"Mały Pudzian\""
    " --username malypudzian2"
    " --email malypudzian@amorek.pl" # (not a student email)
    " --headless"
    " 2>&1"
)
assert status != 0
assert ("Exception: Registration requires manual approval" in output)
