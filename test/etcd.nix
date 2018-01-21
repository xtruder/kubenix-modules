{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.etcd = {
    module = "etcd";
    configuration.clusterState = "existing";
  };
}
