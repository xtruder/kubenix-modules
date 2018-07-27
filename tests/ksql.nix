{ config, ... }:

{
  require = [
    ./test.nix
    ../modules/zookeeper.nix
    ../modules/kafka.nix
    ../modules/ksql.nix
  ];

  kubernetes.modules = {
    zookeeper.configuration = {
      replicas = 4;
    };

    kafka.configuration = {
      zookeeper.servers = [
        "zookeeper-0.zookeeper:2181"
        "zookeeper-1.zookeeper:2181"
        "zookeeper-2.zookeeper:2181"
      ];
    };

    ksql.configuration = {
      bootstrap.servers = ["kafka-0.kafka:9093" "kafka-1.kafka:9093" "kafka-2.kafka:9093"];
    };
  };
}
