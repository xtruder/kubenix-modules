{ config, ... }:

{
  require = [ ./test.nix ../modules/zookeeper.nix ];

  kubernetes.modules.zookeeper.configuration = {
    replicas = 4;
  };
}
