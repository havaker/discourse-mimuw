This repository defines the configuration of the MIMUW students Discourse forum.
It's in a very early stage of development and at the moment it's more of a proof of concept than a working solution.

The core of this repo is a Nix flake that defines the system configuration of a Discourse server instance.
Usage of Nix flakes is dictated by the desire to have a reproducible, declarative and transparent configuration of the forum.
Everybody can see what the forum is configured to, propose changes and see the effects of those changes using the local development environment.

## Development

Requirements:
- GNU/Linux (or maybe macOS?) system.
- [Nix package manager](https://nixos.wiki/wiki/Nix_package_manager) installed.
- [Flakes](https://nixos.wiki/wiki/Flakes) enabled in your Nix installation.

### Running a local test instance

The easiest way to run a local test instance is to use the provided `vm` package output.
The following command will build and run a virtual machine image with the properly configured Discourse service:
```bash
nix run .#vm
```
After the VM boots up, you can access the forum at `http://localhost:8080`.
You may need to wait some time after boot for the discourse service startup to finish.

Invoking `sudo journalctl -f` in the VM will show you the system logs.

### Formatting and error checking

To format the Nix code in this repository, run:
```bash
nix fmt
```

To check if the Nix flake is valid, run:
```bash
nix flake check
```
