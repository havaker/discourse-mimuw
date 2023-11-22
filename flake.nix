{
  description = "Discourse test instance configuration";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
  };

  # This flake defines a system configuration that includes Discourse. In this
  # context, the system configuration means a complete specification of:
  # - Packages installed on the system
  # - Services running on the system
  # - Configuration of that services
  #
  # The goal of defining in such manner is to make it:
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
  # configuration (`outputs.nixosSystem.*`).
  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
      };
    in
    {
      formatter.${system} = pkgs.nixpkgs-fmt;

      # This modules specifies the configuration that are both:
      # - Not specific to Discourse
      # - Valid for production and development configuration
      nixosModules.base = { ... }: {
        # Enable fish shell;)))
        programs.fish.enable = true;

        system.stateVersion = "23.05";
      };

      # This module specifies the Discourse's configuration options that are
      # used in both the production and development configuration. For example,
      # site title is included here, because it should be the same in both
      # configurations. Hostname is not included here, because in production it
      # should point to some real domain, while in development it should point
      # to localhost.
      nixosModules.discourse = { ... }: {
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

      # This module defines the discourse configuration for local development.
      # It is intended to be used as a part of a virtual machine configuration,
      # which can be run using `nix run .#vm`.
      #
      # Development configuration differs from the production one in the
      # following ways:
      # - No TLS is used (ACME is disabled).
      # - Domain name is set to localhost.
      # - Port 8080 is used instead of 80.
      # - Mailhog is used as a mail server, instead of a real one (it allows to
      #   inspect sent emails).
      # - Discourse admin password is set to a fixed value.
      # - A test user (with root privileges) is automatically logged in.
      nixosModules.dev = { config, lib, ... }: {
        # These options are passed to the quemu that runs the dev VM locally.
        virtualisation = {
          graphics = false;
          memorySize = 4096;
          cores = 4;
          # Expose Discourse at port 8080 (Mailhog at 8081) on the host system.
          # This makes it possible to access the Discourse instance and Mailhog
          # UI from the host-system browser.
          forwardPorts = [
            { from = "host"; host.port = 8080; guest.port = config.services.nginx.defaultHTTPListenPort; }
            { from = "host"; host.port = 8081; guest.port = config.services.mailhog.uiPort; }
          ];
        };

        # Allow access from host to the VM instances of Discourse and Mailhog UI.
        networking.firewall.allowedTCPPorts = [
          config.services.mailhog.uiPort
          config.services.nginx.defaultHTTPListenPort
        ];

        services.discourse = {
          # Set the domain name used by Discourse to localhost. Without this
          # setting, accessing Discourse from the host system at
          # http://localhost:8080 would result in Discourse rejecting the
          # request.
          hostname = "localhost";

          # Stuff related to TLS is not needed in the development configuration.
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

          # Hardcode the admin password for the local development purposes.
          admin.passwordFile = "${pkgs.writeText "admin-pass" "qwerasdfZXCV123"}";
        };

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

        # Fake SMTP server that allows to inspect sent emails.
        services.mailhog = {
          enable = true;
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

        # Force fish to use 256 colors instead of none.
        environment.variables.TERM = "xterm-256color";
      };

      # Defines a virtual machine configuration for local development.
      nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.base
          self.nixosModules.discourse
          (x: { virtualisation.vmVariant = self.nixosModules.dev x; })
        ];
      };

      # By packaging the VM configuration, it can be run with a simple
      # `nix run# .#vm`.
      packages.x86_64-linux.vm =
        self.nixosConfigurations.vm.config.system.build.vm;

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.nixd
        ];
      };
    };
}
