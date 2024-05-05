{
  description = "pahs";

  inputs = {
    haskellNix.url = "github:input-output-hk/haskell.nix";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    devshell.url = "github:numtide/devshell";
  };

  nixConfig = {
    extra-substituters = [ "https://cache.iog.io" ];
    extra-trusted-public-keys =
      [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" ];
  };

  outputs = inputs@{ self, flake-utils, haskellNix, devshell, nixpkgs, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "x86_64-darwin" ] (system:
      let
        overlays = [
          haskellNix.overlay
          (final: prev: {
            # This overlay adds our project to pkgs
            pahs = final.haskell-nix.project' {
              src = ./.;
              compiler-nix-name = "ghc964";
            };
          })
          devshell.overlays.default
        ];
        pkgs = import nixpkgs {
          inherit system overlays;
          inherit (haskellNix) config;
        };
        flake = pkgs.pahs.flake { };
        shellWithToml = tomls:
          pkgs.pahs.shellFor {
            exactDeps = false;
            withHoogle = true;
            inputsFrom = [
              (pkgs.devshell.mkShell {
                name = "pahs";
                imports = map pkgs.devshell.importTOML
                  ([ ./env_config/common.toml ] ++ tomls);
              })
            ];
            tools = {
              cabal = "latest";
              fourmolu = "latest";
              hlint = "latest";
              cabal-fmt = "latest";
              haskell-language-server = "latest";
            };
          };
      in flake // {
        packages = rec {
          pahs-lib = flake.packages."pahs:lib:pahs";
          pahs-type = flake.packages."pahs:exe:pahs-type";
          default = pahs-type;
        };
        devShells = { default = shellWithToml [ ]; };
      });

}
