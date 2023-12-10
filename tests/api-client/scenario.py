# See https://nixos.org/manual/nixos/stable/#ssec-machine-objects for
# documentation of methods available on `server` and `client` objects.

start_all()
server.wait_for_unit("discourse.service")

# Get the API key for interacting with Discourse.
api_key = server.succeed("cat /var/lib/discourse/api/key")
api_key = api_key[:-1]  # Remove the trailing newline.

client.succeed(f"env DISCOURSE_API_KEY='{api_key}' api-test")