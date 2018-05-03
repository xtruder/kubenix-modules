{ config, k8s, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.etcd = {};

  kubernetes.modules.vault = {
    module = "vault";
    configuration = {
      replicas = 3;
      configuration = {
        storage.etcd = {
          address = "http://etcd:2379";
          etcd_api = "v3";
          ha_enabled = "true";
        };
      };
      tls.additionalDomains = ["vault.example.com"];
    };
  };
}
