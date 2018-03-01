{ pkgs ? import <nixpkgs> {} }:

with pkgs.lib;

let
  kubenix = import (builtins.fetchGit {
    url = "https://github.com/xtruder/kubenix.git";
  }) { inherit pkgs; };

  globalConfig = {config, ...}: {
    config.kubernetes.version = "1.8";
  };
in {
  services = import ./services/module-list.nix;

  tests = {
    rabbitmq = kubenix.buildResources {
      configuration.imports = [./test/rabbitmq.nix globalConfig];
    };

    elasticsearch = kubenix.buildResources {
      configuration.imports = [./test/elasticsearch.nix globalConfig];
    };

    elasticsearch-curator = kubenix.buildResources {
      configuration.imports = [./test/elasticsearch-curator.nix globalConfig];
    };

    redis = kubenix.buildResources {
      configuration.imports = [./test/redis.nix globalConfig];
    };

    nginx = kubenix.buildResources {
      configuration.imports = [./test/nginx.nix globalConfig];
    };

    galera = kubenix.buildResources {
      configuration.imports = [./test/galera.nix globalConfig];
    };

    etcd-operator = kubenix.buildResources {
      configuration.imports = [./test/etcd-operator.nix globalConfig];
    };

    deployer = kubenix.buildResources {
      configuration.imports = [./test/deployer.nix globalConfig];
    };

    rippled = kubenix.buildResources {
      configuration.imports = [./test/rippled.nix globalConfig];
    };

    zetcd = kubenix.buildResources {
      configuration.imports = [./test/zetcd.nix globalConfig];
    };

    kibana = kubenix.buildResources {
      configuration.imports = [./test/kibana.nix globalConfig];
    };

    parity = kubenix.buildResources {
      configuration.imports = [./test/parity.nix globalConfig];
    };

    mediawiki = kubenix.buildResources {
      configuration.imports = [./test/mediawiki.nix globalConfig];
    };

    beehive = kubenix.buildResources {
      configuration.imports = [./test/beehive.nix globalConfig];
    };

    minio = kubenix.buildResources {
      configuration.imports = [./test/minio.nix globalConfig];
    };

    prometheus = kubenix.buildResources {
      configuration.imports = [./test/prometheus.nix globalConfig];
    };

    prometheus-kubernetes = kubenix.buildResources {
      configuration.imports = [./test/prometheus-kubernetes.nix globalConfig];
    };

    grafana = kubenix.buildResources {
      configuration.imports = [./test/grafana.nix globalConfig];
    };

    kube-lego-gce = kubenix.buildResources {
      configuration.imports = [./test/kube-lego-gce.nix globalConfig];
    };

    pachyderm = kubenix.buildResources {
      configuration.imports = [./test/pachyderm.nix globalConfig];
    };

    etcd = kubenix.buildResources {
      configuration.imports = [./test/etcd.nix globalConfig];
    };

    local-volume-provisioner = kubenix.buildResources {
      configuration.imports = [./test/local-volume-provisioner.nix globalConfig];
    };

    vault = kubenix.buildResources {
      configuration.imports = [./test/vault.nix globalConfig];
    };

    vault-controller = kubenix.buildResources {
      configuration.imports = [./test/vault-controller.nix globalConfig];
    };

    vault-ui = kubenix.buildResources {
      configuration.imports = [./test/vault-ui.nix globalConfig];
    };
  };
}
