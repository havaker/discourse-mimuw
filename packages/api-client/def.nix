# For more details on what is going on here, see a similar but better
# documented example at ../selenium-scenarios/def.nix
{ cacert
, discourse
, fetchFromGitHub
, fixup_yarn_lock
, lib
, python3Packages
, runCommand
, stdenv
, swagger-codegen3
}:
let
  # Just an alias for the assets package of discourse.
  assets = discourse.passthru.assets;
  # The grand goal here is to generate a Python package that can be used to
  # interact with the Discourse API.
  #
  # From the discourse_api_docs repo we can see that it is possible to
  # generate a swagger spec file from the discourse source code. Having this
  # spec file, we can then generate a python package with the help of
  # swagger-codegen3.
  #
  # It all seems like a rather simple task - discourse_api_docs repo's
  # README.md says to just run `rake rswag:specs:swaggerize` and the swagger
  # spec file (openapi.yaml) will be appear. Unfortunately, this is not the
  # case. The rake task fails without the proper development environment set
  # up. This proper development environment consists of a running redis +
  # postgresql server (!) and doing a bunch of things with yarn...
  #
  # To avoid having to write a bunch of Nix code to set up this development
  # environment (and to avoid having to maintain it), I chose to reuse the
  # Discourse assets package's derivation. The derivation already does some
  # stuff with yarn, postgresql and redis. The only thing that I had to add
  # was to extend the preBuild phase to prepare a `discourse_test` database
  # and run a migration on it. I don't really know why is it necessary for the
  # swagger spec generation, the word of web dev is a mysterious one.
  discourseOpenapiSpecFile = assets.overrideAttrs (oldAttrs: {
    name = "spec";

    # To have a look at what is happening in `oldAttrs.preBuild`, see the
    # discourse assets derivation at:
    # https://github.com/NixOS/nixpkgs/blob/b4372c4924d9182034066c823df76d6eaf1f4ec4/pkgs/servers/web-apps/discourse/default.nix#L256
    #
    # (ノಠ益ಠ) ノ彡 ┻━┻
    preBuild = oldAttrs.preBuild + ''
      psql -d postgres -tAc 'CREATE DATABASE "discourse_test" OWNER "discourse"'
      psql 'discourse_test' -tAc "CREATE EXTENSION IF NOT EXISTS pg_trgm"
      psql 'discourse_test' -tAc "CREATE EXTENSION IF NOT EXISTS hstore"

      substituteInPlace spec/swagger_helper.rb \
        --replace "openapi: \"3.1.0\"" "openapi: \"3.0.3\""

      export RAILS_ENV=test
      bundle exec rake db:migrate >/dev/null
    '';

    # After slaying the dragons in the preBuild phase, we can finally run the
    # rake task to generate the swagger spec file.
    buildPhase = ''
      runHook preBuild
      bundle exec rake rswag:specs:swaggerize
    '';

    # Yay! After the buildPhase we get the swagger spec file, now we can build
    # the python package.
    installPhase = ''
      mkdir -p $out
      cp openapi/openapi.yaml $out/openapi.yaml
    '';

    outputs = [ "out" ];
  });
  # Generate the client library python sources from the openapi.yaml file obtained
  # from the discourseOpenapiSpecFile derivation.
  generatedSources =
    let
      swaggerConfig = {
        "packageName" = "discourse_client";
        "projectName" = "Swagger Discourse API";
      };
      configFile = builtins.toFile "config.json" (builtins.toJSON swaggerConfig);
      # The command to generate the Python sources.
      command = ''
        swagger-codegen3 generate -l python -c ${configFile} -i ${discourseOpenapiSpecFile}/openapi.yaml -o $out
      '';
    in
    runCommand "generated-sources"
      {
        buildInputs = [ swagger-codegen3 ];
      }
      command;
in
# Oh that was easy, now we can build the python package;)))
python3Packages.buildPythonPackage rec {
  pname = "discourse_client";
  version = "1.0.0";

  # Use the generated sources to build the Python package.
  src = generatedSources;

  # Swagger uses those dependencies in the generated Python sources.
  propagatedBuildInputs = with python3Packages; [
    certifi
    six
    python-dateutil
    urllib3
  ];
}


