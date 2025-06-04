{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    fenix.url = "github:nix-community/fenix";

    crane.url = "github:ipetkov/crane";

    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      fenix,
      crane,
      treefmt-nix,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forEachSupportedSystem =
        f:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          let
            pkgs = import nixpkgs {
              inherit system;
              overlays = [ fenix.overlays.default ];
            };

            rustToolchain = pkgs.fenix.stable.withComponents [
              "cargo"
              "rustc"
              "rustfmt"
              "rust-std"
              "rust-analyzer"
              "clippy"
            ];

            # more info on https://crane.dev/API.html
            craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

            cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);

            craneArgs = {
              pname = cargoToml.workspace.package.name or cargoToml.package.name;
              version = cargoToml.workspace.package.version or cargoToml.package.version;

              src = craneLib.cleanCargoSource ./.;

              strictDeps = true;

              # can add `nativeBuildInputs` or `buildInputs` here

              nativeBuildInputs = [
                pkgs.pkg-config
              ];

              buildInputs = [
                pkgs.openssl
              ];

              env = {
                # print backtrace on compilation failure
                RUST_BACKTRACE = "1";

                # treat warnings as errors
                RUSTFLAGS = "-Dwarnings";
                RUSTDOCFLAGS = "-Dwarnings";
              };
            };

            cargoArtifacts = craneLib.buildDepsOnly craneArgs;

            craneBuildArgs = craneArgs // {
              src = self;
              inherit cargoArtifacts;
            };

            treefmtEval = treefmt-nix.lib.evalModule pkgs (
              import ./treefmt.nix { inherit rustToolchain cargoToml; }
            );

            treefmt = treefmtEval.config.build.wrapper;
          in
          f {
            inherit
              cargoArtifacts
              craneArgs
              craneBuildArgs
              craneLib
              pkgs
              rustToolchain
              system
              treefmt
              treefmtEval
              ;
          }
        );
    in
    {
      devShells = forEachSupportedSystem (
        {
          pkgs,
          rustToolchain,
          treefmt,
          craneBuildArgs,
          system,
          ...
        }:
        {
          default = self.devShells.${system}.full;

          full = pkgs.mkShell {
            nativeBuildInputs = [
              rustToolchain
              treefmt
            ] ++ (craneBuildArgs.nativeBuildInputs or [ ]);

            buildInputs = craneBuildArgs.buildInputs or [ ];
          };

          toolchainOnly = pkgs.mkShell {
            nativeBuildInputs = [
              rustToolchain
            ];
          };
        }
      );

      formatter = forEachSupportedSystem ({ treefmt, ... }: treefmt);

      packages = forEachSupportedSystem (
        {
          craneLib,
          craneBuildArgs,
          system,
          ...
        }:
        {
          default = craneLib.buildPackage craneBuildArgs;

          docs = craneLib.cargoDoc (
            craneBuildArgs
            // {
              # used to disable `--no-deps`, which crane enables by default,
              # so we include all packages in the resulting docs, to have fully-functional
              # offline docs
              cargoDocExtraArgs = "";
            }
          );
        }
      );

      checks = forEachSupportedSystem (
        {
          craneLib,
          craneBuildArgs,
          treefmtEval,
          ...
        }:
        {
          # can also use `cargoNextest`
          test = craneLib.cargoTest craneBuildArgs;

          doc = craneLib.cargoDoc craneBuildArgs;

          clippy = craneLib.cargoClippy craneBuildArgs;

          treefmt = treefmtEval.config.build.check self;
        }
      );
    };
}
