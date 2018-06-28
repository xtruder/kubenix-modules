{ config, ... }:

{
  require = [
    ./test.nix
    ../modules/zetcd.nix
    ../modules/etcd-operator.nix
  ];

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
