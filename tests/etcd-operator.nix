{ config, ... }:

{
  require = [./test.nix ../modules/etcd-operator.nix];

  kubernetes.modules.etcd-operator = {
    module = "etcd-operator";
  };

  kubernetes.modules.etcd = {
    module = "etcd-cluster";
    configuration.size = 3;
  };
}
