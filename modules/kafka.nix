{ config, lib, k8s, images, ... }:

with lib;
with k8s;

{
  config.kubernetes.moduleDefinitions.kafka.module = {config, module, ...}: {
    options = {
      image = mkOption {
        description = "Image to use";
        type = types.str;
        default = config.kubernetes.dockerRegistry + "/${images.kafka.image.fullName}";
      };

      replicas = mkOption {
        description = "Number of kafka replicas to run";
        type = types.int;
        default = 3;
      };

      zookeeper = {
        servers = mkOption {
          description = "List of zookeeper servers";
          type = types.listOf types.str;
          example = ["zk-0.zk-svc:2181" "zk-1.zk-svc:2181" "zk-2.zk-svc:2181"];
        };
      };

      opts = mkOption {
        description = "Kafka options";
        type = types.attrs;
      };
    };

    config = {
      opts = {
        listeners = "PLAINTEXT://\${HOSTNAME}.${module.name}:9093";
        "zookeeper.connect" = concatStringsSep "," config.zookeeper.servers;
        "auto.create.topics.enable" = "true";
        "auto.leader.rebalance.enable" = "true";
        "background.threads" = "10";
        "delete.topic.enable" = "true";
        "leader.imbalance.check.interval.seconds" = "300";
        "leader.imbalance.per.broker.percentage" = "10";
        "log.flush.interval.messages" = "9223372036854775807";
        "log.flush.offset.checkpoint.interval.ms" = "60000";
        "log.flush.scheduler.interval.ms" = "9223372036854775807";
        "log.retention.bytes" = "-1"; 
        "log.retention.hour" = "168";
        "log.roll.hours" = "168";
        "log.roll.jitter.hours" = "0";
        "log.segment.bytes" = "1073741824";
        "log.segment.delete.delay.ms" = "60000";
        "message.max.bytes" = "1000012";
        "min.insync.replicas" = "1";
        "num.io.threads" = "8";
        "num.network.threads" = "3";
        "num.recovery.threads.per.data.dir" = "1";
        "num.replica.fetchers" = "1";
        "offset.metadata.max.bytes" = "4096";
        "offsets.commit.required.acks" = "-1";
        "offsets.commit.timeout.ms" = "5000";
        "offsets.load.buffer.size" = "5242880";
        "offsets.retention.check.interval.ms" = "600000";
        "offsets.retention.minutes" = "1440";
        "offsets.topic.compression.codec" = "0";
        "offsets.topic.num.partitions" = "50";
        "offsets.topic.replication.factor" = "3";
        "offsets.topic.segment.bytes" = "104857600";
        "queued.max.requests" = "500";
        "quota.consumer.default" = "9223372036854775807";
        "quota.producer.default" = "9223372036854775807";
        "replica.fetch.min.bytes" = "1";
        "replica.fetch.wait.max.ms" = "500";
        "replica.high.watermark.checkpoint.interval.ms" = "5000";
        "replica.lag.time.max.ms" = "10000";
        "replica.socket.receive.buffer.bytes" = "65536";
        "replica.socket.timeout.ms" = "30000";
        "request.timeout.ms" = "30000";
        "socket.receive.buffer.bytes" = "102400";
        "socket.request.max.bytes" = "104857600";
        "socket.send.buffer.bytes" = "102400";
        "unclean.leader.election.enable" = "true";
        "zookeeper.session.timeout.ms" = "6000";
        "zookeeper.set.acl" = "false";
        "broker.id.generation.enable" = "true";
        "connections.max.idle.ms" = "600000";
        "controlled.shutdown.enable" = "true";
        "controlled.shutdown.max.retries" = "3";
        "controlled.shutdown.retry.backoff.ms" = "5000";
        "controller.socket.timeout.ms" = "30000";
        "default.replication.factor" = "1";
        "fetch.purgatory.purge.interval.requests" = "1000";
        "group.max.session.timeout.ms" = "300000";
        "group.min.session.timeout.ms" = "6000";
        "log.cleaner.backoff.ms" = "15000";
        "log.cleaner.dedupe.buffer.size" = "134217728";
        "log.cleaner.delete.retention.ms" = "86400000";
        "log.cleaner.enable" = "true";
        "log.cleaner.io.buffer.load.factor" = "0.9";
        "log.cleaner.io.buffer.size" = "524288";
        "log.cleaner.io.max.bytes.per.second" = "1.7976931348623157E308";
        "log.cleaner.min.cleanable.ratio" = "0.5";
        "log.cleaner.min.compaction.lag.ms" = "0";
        "log.cleaner.threads" = "1";
        "log.cleanup.policy" = "delete";
        "log.index.interval.bytes" = "4096";
        "log.index.size.max.bytes" = "10485760";
        "log.message.timestamp.difference.max.ms" = "9223372036854775807";
        "log.message.timestamp.type" = "CreateTime";
        "log.preallocate" = "false";
        "log.retention.check.interval.ms" = "300000";
        "max.connections.per.ip" = "2147483647";
        "num.partitions" = "1";
        "producer.purgatory.purge.interval.requests" = "1000";
        "replica.fetch.backoff.ms" = "1000";
        "replica.fetch.max.bytes" = "1048576";
        "replica.fetch.response.max.bytes" = "10485760";
        "reserved.broker.max.id" = "1000"; 
        "log.dir" = "/data";
        "broker.id" = "\${HOSTNAME##*-}";
      };

      kubernetes.resources.statefulSets.kafka = {
        spec = {
          serviceName = module.name;
          replicas = config.replicas;
          podManagementPolicy = "Parallel";
          template = {
            metadata.labels.app = module.name;
            spec = {
              containers.kafka = {
                image = config.image;
                imagePullPolicy = "Always";
                resources.requests = {
                  memory = "1Gi";
                  cpu = "500m";
                };
                ports = [{
                  containerPort = 9093;
                  name = "server";
                }];
                command = [
                  "/bin/sh" "-c"
                  ("/bin/kafka-server-start.sh /config/server.properties " + (
                    concatStringsSep " " (mapAttrsToList (key: val:
                      "--override ${key}=${val}"
                    ) config.opts)
                  ))
                ];
                env = {
                  KAFKA_HEAP_OPTS.value = "-Xmx512M -Xms512M";
                  KAFKA_OPTS.value = "-Dlogging.level=INFO";
                };
                volumeMounts = [{
                  name = "datadir";
                  mountPath = "/data";
                }];
              };
            };
          };
          volumeClaimTemplates = [{
            metadata.name = "datadir";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = "10Gi";
            };
          }];
        };
      };

      kubernetes.resources.services.kafka = {
        metadata.name = module.name;
        metadata.labels.app = module.name;

        spec = {
          clusterIP = "None";
          ports = [{
            port = 9093;
            name = "server";
          }];
          selector.app = module.name;
        };
      };
    };
  };
}
