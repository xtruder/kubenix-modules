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

  examples = {
    vault-prod = kubenix.buildResources {
      configuration.imports = [./examples/vault/vault-prod.nix globalConfig];
    };

    ca-deployer = kubenix.buildResources {
      configuration.imports = [./examples/deployer/ca-deployer.nix globalConfig];
    };

    logs = kubenix.buildResources {
      configuration.imports = [./examples/logs/default.nix globalConfig];
    };

    nginx-ingress-external-dns = kubenix.buildResources {
      configuration.imports = [./examples/ingress/nginx-ingress-external-dns.nix globalConfig];
    };

    prometheus = kubenix.buildResources {
      configuration.imports = [./examples/prometheus/default.nix globalConfig];
    };
  };

  tests = {
    bitcoind = kubenix.buildResources {
      configuration.imports = [./test/bitcoind.nix globalConfig];
    };

    dashd = kubenix.buildResources {
      configuration.imports = [./test/dashd.nix globalConfig];
    };

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

    vault-prod = kubenix.buildResources {
      configuration.imports = [./test/vault-prod.nix globalConfig];
    };

    vault-controller = kubenix.buildResources {
      configuration.imports = [./test/vault-controller.nix globalConfig];
    };

    vault-controller-k8s-auth = kubenix.buildResources {
      configuration.imports = [./test/vault-controller-k8s-auth.nix globalConfig];
    };

    vault-ui = kubenix.buildResources {
      configuration.imports = [./test/vault-ui.nix globalConfig];
    };

    vault-login-k8s = kubenix.buildResources {
      configuration.imports = [./test/vault-login-k8s.nix globalConfig];
    };

    logstash = kubenix.buildResources {
      configuration.imports = [./test/logstash.nix globalConfig];
    };

    influxdb = kubenix.buildResources {
      configuration.imports = [./test/influxdb.nix globalConfig];
    };

    kubelog = kubenix.buildResources {
      configuration.imports = [./test/kubelog.nix globalConfig];
    };

    secret-restart-controller = kubenix.buildResources {
      configuration.imports = [./test/secret-restart-controller.nix globalConfig];
    };

    selfsigned-cert-deployer = kubenix.buildResources {
      configuration.imports = [./test/selfsigned-cert-deployer.nix globalConfig];
    };

    nginx-ingress = kubenix.buildResources {
      configuration.imports = [./test/nginx-ingress.nix globalConfig];
    };

    mongo = kubenix.buildResources {
      configuration.imports = [./test/mongo.nix globalConfig];
    };

    pritunl = kubenix.buildResources {
      configuration.imports = [./test/pritunl.nix globalConfig];
    };

    cloud-sql-proxy = kubenix.buildResources {
      configuration.imports = [./test/cloud-sql-proxy.nix globalConfig];
    };

    mariadb = kubenix.buildResources {
      configuration.imports = [./test/mariadb.nix globalConfig];
    };

    k8s-snapshot = kubenix.buildResources {
      configuration.imports = [./test/k8s-snapshot.nix globalConfig];
    };

    goldfish = kubenix.buildResources {
      configuration.imports = [./test/goldfish.nix globalConfig];
    };
  };
}
