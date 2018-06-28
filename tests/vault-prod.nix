{ config, k8s, ... }:

{
  require = [
    ./test.nix
    ../modules/vault.nix
    ../modules/etcd.nix
  ];

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
