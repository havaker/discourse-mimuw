{
  description = "MIMUW Discourse instance configuration";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
  };

  # This flake defines a system configuration that includes Discourse. In this
  # context, the system configuration means a complete specification of:
  # - Packages installed on the system
  # - Services running on the system
  # - Configuration of that services
  #
  # The goal of defining it in such manner is to make it:
  # - Easy to deploy it to some machine
  # - Reproducible (the same configuration will always result in the same
  #   system)
  # - Transparent (it is easy to see what exactly is installed and how it is
  #   configured)
  # - Easy to test (the flake provides a way to run a dev version of the
  #   configuration in a easily spun up virtual)
  #
  # The configuration is defined in a modular way. Each module
  # (`outputs.nixosModules.*`) defines a specific part of the configuration.
  # The modules are then combined together to form a complete system
  # configuration -- for example nixosModules.base is combined (using the
  # `include` attribute) with nixosModules.test to form a configuration that is
  # used for testing.
  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
      };
    in
    {
      # Running `nix fmt` in the project's root directory will format all
      # *.nix files in the project using nixpkgs-fmt.
      formatter.${system} = pkgs.nixpkgs-fmt;

      # This modules specifies the configuration that is both valid for
      # production, development configuration and tests.
      # For example, Discourse's site title is included here, because it should
      # be the same in both configurations. Hostname is not included here,
      # because in production it should point to some real domain, while in
      # development it should point to localhost.
      nixosModules.base = { ... }: {
        system.stateVersion = "23.05";

        services.postgresql.package = pkgs.postgresql_13;

        services.discourse = {
          enable = true;
          admin = {
            username = "balenciaga";
            email = "balenciaga@mimuw.edu.pl";
            fullName = "Balenciaga";
          };
          siteSettings = {
            required = {
              title = "Forum Studenckie WMIMUW";
              short_site_description = "rm -rf facebook_groopki";
            };
          };
        };
      };

      # This module defines the discourse server configuration for testing
      # purposes. It is intended to be used as a part of the flake checks.
      #
      # Test configuration differs from the production one in the
      # following ways:
      # - No TLS is used (ACME is disabled).
      # - Domain name is set to "server".
      # - Mailhog is used as a mail server, instead of a real one (it allows to
      #   inspect sent emails).
      # - Discourse admin password is set to a fixed value.
      nixosModules.test = { config, lib, ... }: {
        imports = [
          self.nixosModules.base
        ];

        # Allow external access to Discourse and Mailhog.
        networking.firewall.allowedTCPPorts = [
          config.services.nginx.defaultHTTPListenPort
          config.services.mailhog.uiPort
        ];

        services.discourse = {
          hostname = lib.mkDefault "server";

          # Stuff related to TLS is not needed in the test configuration.
          enableACME = false;

          mail = {
            # Send outgoing emails through Mailhog - a fake SMTP server that
            # allows to inspect sent emails.
            outgoing = {
              username = "";
              serverAddress = "localhost";
              opensslVerifyMode = "none";
              port = config.services.mailhog.smtpPort;
            };
            contactEmailAddress = "admin@localhost";
          };

          # Hardcode the admin password for the testing purposes.
          admin.passwordFile = "${pkgs.writeText "admin-pass" "qwerasdfZXCV123"}";
        };

        # Fake SMTP server that allows to inspect sent emails.
        services.mailhog = {
          enable = true;
        };
      };

      # This module defines the discourse configuration for local development.
      # Local development might consist of: visualizing changes to the
      # discourse configuration by browsing the forum using a normal web
      # browser, tweaking visual settings, exploring forum's capabilities.
      #
      # Development configuration inherits most of defined options from the
      # test configuration (self.nixosModules.test). It differs from it in the
      # the following ways:
      # - Domain name is set to localhost.
      # - Port 8080 is used instead of 80.
      # - A test user (with root privileges) is automatically logged in.
      #
      # It is intended to be used as a part of a virtual machine configuration,
      # which can be run using `nix run .#vm`.
      nixosModules.dev = { config, lib, ... }: {
        imports = [
          # Include the test configuration.
          self.nixosModules.test
        ];

        # These options are passed to the quemu that runs the dev VM locally.
        virtualisation = {
          graphics = false;
          memorySize = 4096;
          cores = 8;
          # Expose Discourse at port 8080 (Mailhog at 8081) on the host system.
          # This makes it possible to access the Discourse instance and Mailhog
          # UI from the host-system browser.
          forwardPorts = [
            { from = "host"; host.port = 8080; guest.port = config.services.nginx.defaultHTTPListenPort; }
            { from = "host"; host.port = 8081; guest.port = config.services.mailhog.uiPort; }
          ];
        };

        # Set the domain name used by Discourse to localhost. Without this
        # setting, accessing Discourse from the host system at
        # http://localhost:8080 would result in Discourse rejecting the
        # request.
        # The setting is using `lib.mkForce` to make it possible to override
        # the value specified in the test configuration.
        services.discourse.hostname = lib.mkForce "localhost";

        # Discourse expects to be run on port 80, but we want to be exposed on
        # host system's localhost:8080. This need is dictated by the fact that
        # setting up a service on port 80 requires root privileges, which
        # shouldn't be required for local development.
        #
        # By leveraging the fact that Discourse is already run behind Nginx, we
        # can use it to rewrite requests in such way, that Discourse would be
        # tricked into thinking that the request destination is port 80.
        #
        # That's a bit hacky, but it makes us able to reuse the options that
        # NixOS provides for configuration of a Discourse service. Otherwise,
        # we would have to setup the Discourse installation in the development
        # configuration from scratch:
        # https://meta.discourse.org/t/install-discourse-on-ubuntu-or-debian-for-development/14727
        services.nginx.virtualHosts."localhost" = {
          extraConfig = ''
            proxy_set_header Host localhost;
            proxy_redirect http://localhost/ http://localhost:8080;

            proxy_hide_header Content-Security-Policy;
          '';
        };

        # Basic networking configuration.
        networking.interfaces.eth0.useDHCP = true;

        # Setup a test user that is:
        # - Automatically logged in
        # - Has root privileges available via `sudo`
        services.getty.autologinUser = "test";
        users.users.test = {
          isNormalUser = true;
          shell = pkgs.fish;
          extraGroups = [ "wheel" ];
        };
        security.sudo.wheelNeedsPassword = false;

        # Enable fish shell;)))
        programs.fish.enable = true;
        # Force fish to use 256 colors instead of none.
        environment.variables.TERM = "xterm-256color";
      };

      # Defines a virtual machine configuration for local development.
      # By packaging the VM configuration, it can be run with a simple
      # `nix run# .#vm`.
      packages.x86_64-linux.vm =
        let
          vm = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              (x: { virtualisation.vmVariant = self.nixosModules.dev x; })
            ];
          };
        in
        vm.config.system.build.vm;

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.nixd
        ];
      };
    };
}
