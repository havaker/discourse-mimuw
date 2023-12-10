# For more details on what is going on here, see a similar but better
# documented example at ../selenium-scenarios/def.nix
{ lib
, python3Packages
}:
python3Packages.buildPythonApplication rec {
  pname = "applier";
  version = "0.0.0";
  src = ./.;

  propagatedBuildInputs = with python3Packages; [
    requests-unixsocket
    requests
  ];
}

