{ pkgs ? import <nixpkgs> {}
, lib ? pkgs.lib
, version ? "1.10"
, kubenix ? import <kubenix> {}
, registry ? "docker.io/gatehub" }:

with lib;

{
  tests = (kubenix.evalModules {
    modules = [
      kubenix.modules.testing

      {
        testing.tests = [
          ./submodules/mariadb/test.nix
          ./submodules/argo-ingress-controller/test.nix
          ./submodules/metacontroller/test.nix
          ./submodules/nginx/test.nix
          ./submodules/nginx-ingress/test.nix
          ./submodules/bitcoind/test.nix
          ./submodules/bitcoincashd/test.nix
          ./submodules/dashd/test.nix
        ];
        testing.defaults = {
          imports = with kubenix.modules; [ k8s docker ];
          kubernetes.version = version;
          docker.registry.url = registry;
        };
      }
    ];
    args = {
      inherit pkgs;
    };
    specialArgs = {
      inherit kubenix;
    };
  }).config;

  module = { config, kubenix, ... }: {
    imports = [ kubenix.modules.submodules ];

    submodules.imports = [
      ./submodules/mariadb/1.x.nix
      ./submodules/argo-ingress-controller/1.x.nix
      ./submodules/metacontroller/1.x.nix
      ./submodules/nginx/1.x.nix
      ./submodules/nginx-ingress/1.x.nix
      ./submodules/bitcoind/1.x.nix
      ./submodules/bitcoincashd/1.x.nix
      ./submodules/dashd/1.x.nix
    ];
  };
}
