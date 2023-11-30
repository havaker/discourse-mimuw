# Defines a derivation that builds a Python application from this directory.
#
# This Nix expression is intended to be used with the `pkgs.callPackage`
# function (see https://nixos-and-flakes.thiscute.world/nixpkgs/callpackage for
# more details about `callPackage`).
{ lib
, python3Packages
, makeWrapper
, firefox
, geckodriver
,
}:
# Using a language-specific package helper - in this case,
# `buildPythonApplication`. See https://nixos.wiki/wiki/Packaging/Python
# for more details.
python3Packages.buildPythonApplication rec {
  pname = "selenium-scenarios"; # Define the name of the package.
  version = "0.0.0"; # Some version is required.
  src = ./.; # Source code of the package is here (./main.py and ./setup.py).

  # main.py depends on selenium
  propagatedBuildInputs = [ python3Packages.selenium ];

  # During the build, we want to wrap the main.py script so that it can find
  # the firefox and geckodriver executables at runtime. `wrapProgram` is a tool
  # that can do this for us. See
  # https://ryantm.github.io/nixpkgs/stdenv/stdenv/#ssec-stdenv-dependencies-overview-example
  # for more details on its usage.
  nativeBuildInputs = [ makeWrapper ];

  # Except for wrapping the main.py script, the postInstall hook is also used
  # to rename the main.py executable to the name of the package, so that it can
  # be run with `nix run`.
  postInstall = ''
    for f in $out/bin/*; do
      wrapProgram "$f" \
        --prefix PATH : ${lib.makeBinPath [firefox geckodriver]}
    done
  '';
}

