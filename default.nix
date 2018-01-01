{ pkgs ? import <nixpkgs> {} }:

with pkgs.lib;

let
  kubenix = import (builtins.fetchGit {
    url = "https://github.com/xtruder/kubenix.git";
  }) { inherit pkgs; };
in {
  services = import ./services/module-list.nix;

  tests = {
    rabbitmq = kubenix.buildResources {
      configuration = ./test/rabbitmq.nix;
    };

    elasticsearch = kubenix.buildResources {
      configuration = ./test/elasticsearch.nix;
    };

    elasticsearch-curator = kubenix.buildResources {
      configuration = ./test/elasticsearch-curator.nix;
    };

    redis = kubenix.buildResources {
      configuration = ./test/redis.nix;
    };

    nginx = kubenix.buildResources {
      configuration = ./test/nginx.nix;
    };

    galera = kubenix.buildResources {
      configuration = ./test/galera.nix;
    };

    etcd = kubenix.buildResources {
      configuration = ./test/etcd.nix;
    };

    deployer = kubenix.buildResources {
      configuration = ./test/deployer.nix;
    };

    rippled = kubenix.buildResources {
      configuration = ./test/rippled.nix;
    };

    zetcd = kubenix.buildResources {
      configuration = ./test/zetcd.nix;
    };

    kibana = kubenix.buildResources {
      configuration = ./test/kibana.nix;
    };

    parity = kubenix.buildResources {
      configuration = ./test/parity.nix;
    };

    beehive = kubenix.buildResources {
      configuration = ./test/beehive.nix;
    };

    minio = kubenix.buildResources {
      configuration = ./test/minio.nix;
    };
  };
}
