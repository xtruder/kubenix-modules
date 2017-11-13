{ pkgs ? import <nixpkgs> {} }:

with pkgs.lib;

let
  nix-kubernetes = import (builtins.fetchgit {
    url = "https://github.com/xtruder/kubenix.git";
  }) { inherit pkgs; };
in {
  test = {
    rabbitmq = nix-kubernetes.buildResources {
      configuration = ./test/rabbitmq.nix;
    };
  };
}
