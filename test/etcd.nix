{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.etcd-operator = {
    module = "etcd-operator";
  };

  kubernetes.modules.etcd = {
    module = "etcd-cluster";
    configuration.size = 3;
  };
}
