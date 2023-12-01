# See https://nixos.org/manual/nixos/stable/#ssec-machine-objects for
# documentation of methods available on `server` and `client` objects.

start_all()

server.wait_for_unit("discourse.service")
server.wait_for_file("/run/discourse/sockets/unicorn.sock")

# Verify that the admin user is able to log in.
client.succeed(
    "verify-login"
    " --address http://server"
    " --username \"$USERNAME\""
    " --headless"
)

# Verify it is possible to register a new user with a email address from
# the trusted students.mimuw.edu.pl domain.
client.succeed(
    "registration"
    " --address http://server"
    " --mailhog-address http://server:8025"
    " --name \"Duży Pudzian\""
    " --username pudzian5"
    " --email duzypudzian5@students.mimuw.edu.pl"
    " --headless"
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
