{ config, ...}:

{
  imports = [
    ./test.nix
    ../modules/kafka.nix
    ../modules/zookeeper.nix
  ];

  config = {
    kubernetes.modules.kafka.configuration = {
      zookeeper.servers = [
        "zookeeper-0.zookeeper:2181"
        "zookeeper-1.zookeeper:2181"
        "zookeeper-2.zookeeper:2181"
      ];
    };

    kubernetes.modules.zookeeper = {};
  };
}