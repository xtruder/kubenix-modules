{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.etcd-operator = {
    module = "etcd-operator";
  };

  kubernetes.modules.etcd = {
    module = "etcd-cluster";
  };

  kubernetes.modules.zetcd = {
    module = "zetcd";
    configuration.endpoints = ["etcd-client:2379"];
  };
}
