(import ../lib.nix) {
  name = "Test of Discourse API Python client";

  nodes = {
    server = { self, pkgs, ... }: {
      imports = [
        self.nixosModules.test
      ];
    };

    client = { self, pkgs, ... }: {
      environment.systemPackages =
        let
          python = pkgs.python3.withPackages (_: [
            self.packages.x86_64-linux.api-client
          ]);
          tester = pkgs.writeScriptBin "api-test" ''
            #!${python}/bin/python
            import discourse_client
            import os

            api_key = os.environ['DISCOURSE_API_KEY']

            config = discourse_client.Configuration()
            config.host = 'http://server'

            d = discourse_client.ApiClient(config)
            d.set_default_header('Api-Key', api_key)
            d.set_default_header('Api-Username', 'system')

            groups = discourse_client.GroupsApi(d)
            g = groups.get_group(id="students")
          '';
        in
        [
          tester
        ];
    };
  };

  testScript = builtins.readFile ./scenario.py;
}
