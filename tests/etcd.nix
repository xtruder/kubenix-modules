{ config, ... }:

{
  require = [./test.nix ../modules/etcd.nix];

  kubernetes.modules.etcd = {
    module = "etcd";
    configuration.clusterState = "existing";
  };
}
