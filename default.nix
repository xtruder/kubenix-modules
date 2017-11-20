{ pkgs ? import <nixpkgs> {} }:

with pkgs.lib;

let
  kubenix = import (builtins.fetchgit {
    url = "https://github.com/xtruder/kubenix.git";
  }) { inherit pkgs; };
in {
  tests = {
    rabbitmq = kubenix.buildResources {
      configuration = ./test/rabbitmq.nix;
    };

    elasticsearch = kubenix.buildResources {
      configuration = ./test/elasticsearch.nix;
    };

    redis = kubenix.buildResources {
      configuration = ./test/redis.nix;
    };
  };
}
