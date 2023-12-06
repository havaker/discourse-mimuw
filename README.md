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

### Running a local development instance

Let's say that you just changed some site setting in `flake.nix` and you want to see how it affects the forum.
The easiest way to do that is to run a local development instance of the forum, and observe the changes from your browser.

To do so, you can use the `vm` package output defined in `flake.nix`.
The following command will build and run a virtual machine image with the properly configured Discourse service:
```bash
nix run '.#vm' # It also works without the ''
```
After the VM boots up, you can access the forum at `http://localhost:8080`.
You may need to wait some time after boot for the Discourse service startup to finish.

- Invoking `journalctl -f` in the VM will show you the system logs.
- Invoking `systemctl status discourse` will also show you the status of the Discourse service e.g. Whether it completed the startup process.

## Testing

To check if the flake evaluates correctly, run:
```bash
nix flake check --no-build
```

The repository contains integration tests that check if the Discourse service defined in the flake's modules is configured correctly.
Tests use the [NixOS testing framework](https://nixos.org/manual/nixos/stable/index.html#sec-nixos-tests) and are defined in the `tests` directory.
They setup client + server virtual machines and run Selenium & API-based acceptance tests.
Although it sounds complicated, running these tests is as simple as:
```bash
nix flake check -L
```

### Formatting

To format the Nix code in this repository, run:
```bash
nix fmt
```
