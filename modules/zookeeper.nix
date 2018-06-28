{ config, lib, k8s, images, ... }:

with lib;
with k8s;

{
  config.kubernetes.moduleDefinitions.zookeeper.module = {config, module, ...}: {
    options = {
      image = mkOption {
        description = "Docker image to use";
        type = types.str;
        default = config.kubernetes.dockerRegistry + "/" + images.zookeeper.image.fullName;
      };

      replicas = mkOption {
        description = "Number of zookeeper replicas to run";
        type = types.int;
        default = 3;
      };

      tickTime = mkOption {
        type = types.int;
        description = ''
            The length of a single tick, which is the basic time unit used by ZooKeeper,
            as measured in milliseconds. It is used to regulate heartbeats, and timeouts.
            For example, the minimum session timeout will be two ticks.
        '';
        default = 2000;
      };

      initTicks = mkOption {
        type = types.int;
        description = ''
          Amount of time, in ticks, to allow followers to connect
          and sync to a leader. Increased this value as needed, if the amount of
          data managed by ZooKeeper is large.
        '';
        default = 10;
      };

      initLimit = mkOption {
        type = types.int;
        description = ''
          Amount of time, in ticks (see tickTime), to allow followers to connect and sync to a leader.
          Increased this value as needed, if the amount of data managed by ZooKeeper is large.
        '';
        default = 5;
      };

      syncLimit = mkOption {
        type = types.int;
        description = ''
          Amount of time, in ticks (see tickTime), to allow followers to sync
          with ZooKeeper. If followers fall too far behind a leader, they will be dropped.
        '';
        default = 2;
      };

      maxClientCnxns = mkOption {
        type = types.int;
        description = ''
          Limits the number of concurrent connections (at the socket level) that
          a single client, identified by IP address, may make to a single member
          of the ZooKeeper ensemble. This is used to prevent certain classes of
          DoS attacks, including file descriptor exhaustion. Setting this to 0 or
          omitting it entirely removes the limit on concurrent connections.
        '';
        default = 60;
      };

      snapRetainCount = mkOption {
        type = types.int;
        description = ''
          When enabled, ZooKeeper auto purge feature retains the
          autopurge.snapRetainCount most recent snapshots and the corresponding
          transaction logs in the dataDir and dataLogDir respectively and deletes the rest.
        '';
        default = 3;
      };

      purgeInterval = mkOption {
        type = types.int;
        description = ''
          The time interval in hours for which the purge task has to be triggered.
          Set to a positive integer (1 and above) to enable the auto purging.
        '';
        default = 3;
      };

      logLevel = mkOption {
        type = types.enum ["INFO" "DEBUG"];
        description = "ZooKeeper log level";
        default = "INFO";
      };

      storage = {
        size = mkOption {
          description = "ZooKeeper storage size";
          type = types.str;
          default = "50Gi";
        };

        class = mkOption {
          description = "ZooKeeper storage class";
          type = types.nullOr types.str;
          default = null;
        };
      };

      heapSize = mkOption {
        description = "Zookeeper heap size";
        type = types.str;
        default = "1024m";
      };

      resources = {
        memory = mkOption {
          description = "Zookeeper memory requirements in megabytes";
          type = types.str;
          default = "1Gi";
        };

        cpu = mkOption {
          description = "Zookeeper cpu requirements";
          type = types.str;
          default = "1000m";
        };
      };

      props = mkOption {
        description = "ZooKeeper properties";
        type = types.attrs;
      };

      log4jProps = mkOption {
        description = "Zookeeper log4j properties";
        type = types.attrs;
      };
    };

    config = {
      props = mkMerge ([{
        dataDir = "/data";
        clientPort = 2181;

        inherit (config) tickTime initLimit syncLimit maxClientCnxns;
        "autopurge.snapRetainCount" = config.snapRetainCount;
        "autopurge.purgeInterval" = config.purgeInterval;
      }] ++ (map (i: {
        "server.${toString i}" = "${module.name}-${toString i}.${module.name}:2888:3888";
      }) (range 0 (config.replicas - 1))));

      log4jProps = {
        "zookeeper.root.logger" = "CONSOLE";
        "zookeeper.console.threshold" = config.logLevel;
        "log4j.rootLogger" = "\${zookeeper.root.logger}";
        "log4j.appender.CONSOLE" = "org.apache.log4j.ConsoleAppender";
        "log4j.appender.CONSOLE.Threshold" = "\${zookeeper.console.threshold}";
        "log4j.appender.CONSOLE.Layout" = "org.apache.log4j.PatternLayout";
        "log4j.appender.CONSOLE.Layout.ConversionPattern" = "%d{ISO8601} [myid:%X{myid}] - %-5p [%t:%C{1}@%L] - %m%n";
      };

      kubernetes.resources.configMaps.zookeeper = {
        metadata = {
          name = module.name;
          labels.app = module.name;
        };
        data = let
          toPropsFile = props:
            concatStringsSep "\n"
              (mapAttrsToList (name: val: "${name}=${toString val}") props);
        in {
          "zoo.cfg" = toPropsFile config.props;
          "log4j.properties" = toPropsFile config.log4jProps;
        };
      };

      kubernetes.resources.statefulSets.zookeeper = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          serviceName = module.name;
          replicas = config.replicas;
          podManagementPolicy = "Parallel";
          template = {
            metadata.labels.app = module.name;
            spec = {
              initContainers.zookeeper-init = {
                image = config.image;
                command = ["/bin/sh" "-c" "echo \${HOSTNAME##*-} > /data/myid"];
                volumeMounts = [{
                  name = "datadir";
                  mountPath = "/data";
                }];
              };

              containers.zookeeper = {
                image = config.image;
                imagePullPolicy = "Always";
                resources.requests = {
                  memory = config.resources.memory;
                  cpu = config.resources.cpu;
                };
                ports = [{
                  containerPort = 2181;
                  name = "server";
                } {
                  containerPort = 2888;
                  name = "leader";
                } {
                  containerPort = 3888;
                  name = "election";
                }];
                command = ["/bin/zkServer.sh" "start-foreground"];
                env.ZOOCFGDIR.value = "/etc/zookeeper";
                volumeMounts = [{
                  name = "datadir";
                  mountPath = "/data";
                } {
                  name = "config";
                  mountPath = "/etc/zookeeper/zoo.cfg";
                  subPath = "zoo.cfg";
                } {
                  name = "config";
                  mountPath = "/etc/zookeeper/log4j.properties";
                  subPath = "log4j.properties";
                }];
                readinessProbe = {
                  exec.command = ["/bin/sh" "-c" ''
                    exec 5<>/dev/tcp/localhost/2181
                    echo -e "ruok" >&5
                    OK=$(cat <&5)

                    if [ "$OK" == "imok" ]; then
                      exit 0
                    else
                      exit 1
                    fi
                  ''];
                  initialDelaySeconds = 30;
                  periodSeconds = 10;
                };
              };
              volumes.config.configMap.name = module.name;
            };
          };
          volumeClaimTemplates = [{
            metadata.name = "datadir";
            spec = {
              accessModes = ["ReadWriteOnce"];
              storageClassName = mkIf (config.storage.class != null) config.storage.class;
              resources.requests.storage = config.storage.size;
            };
          }];
        };
      };

      kubernetes.resources.services.zookeeper = {
        metadata.name = module.name;
        metadata.annotations.
          "service.alpha.kubernetes.io/tolerate-unready-endpoints" = "true";
        metadata.labels.app = module.name;

        spec = {
          clusterIP = "None";
          ports = [{
            port = 2181;
            name = "server";
          } {
            port = 2888;
            name = "leader";
          } {
            port = 3888;
            name = "election";
          }];
          selector.app = module.name;
        };
      };
    };
  };
}
