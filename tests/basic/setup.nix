(import ../lib.nix) {
  name = "Basic Discourse test";

  nodes = {
    server = { self, ... }: {
      imports = [
        self.nixosModules.test
      ];
    };

    client = { self, config, pkgs, ... }: {
      environment.systemPackages = [
        self.packages.x86_64-linux.verify-login
      ];

      environment.sessionVariables = {
        DISCOURSE_USERNAME = "balenciaga";
        DISCOURSE_PASSWORD = "qwerasdfZXCV123";
      };
    };
  };

  testScript = builtins.readFile ./scenario.py;
}
