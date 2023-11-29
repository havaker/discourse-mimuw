start_all()

server.wait_for_unit("discourse.service")
server.wait_for_file("/run/discourse/sockets/unicorn.sock")

client.succeed("verify-login http://server --headless")
