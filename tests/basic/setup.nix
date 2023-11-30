(import ../lib.nix) {
  name = "Basic Discourse test";

  nodes = {
    server = { self, ... }: {
      imports = [
        self.nixosModules.test
      ];
    };

    client = { self, nodes, ... }: {
      environment.systemPackages = [
        self.packages.x86_64-linux.selenium-scenarios
      ];

      # This leaks the password into the store, but it is already in the store
      # by self.nixosModules.test anyway.
      environment.sessionVariables = {
        PASSWORD = builtins.readFile nodes.server.services.discourse.admin.passwordFile;
        USERNAME = nodes.server.services.discourse.admin.username;
      };
    };
  };

  testScript = builtins.readFile ./scenario.py;
}
