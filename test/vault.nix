{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.etcd.module = "etcd";

  kubernetes.modules.vault = {
    module = "vault";
    configuration.configuration = {
      storage.etcd = {
        address = "http://etcd:2379";
        etcd_api = "v3";
        ha_enabled = "true";
        path = "vault7/";
      };
      listener = [{
        tcp = {
          address = "0.0.0.0:8200";
          tls_disable = "true";
        };
      }];
    };
  };
}
