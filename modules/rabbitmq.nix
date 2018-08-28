{ name, lib, config, k8s, ... }:

with lib;
with k8s;

{
  kubernetes.moduleDefinitions.rabbitmq.module = {module, config, ...}: {
    options = {
      image = mkOption {
        description = "Docker image to use";
        type = types.str;
        default = "rabbitmq:3.7";
      };

      replicas = mkOption {
        description = "Number of rabbitmq replicas to run";
        type = types.int;
        default = 3;
      };

      defaultUser = mkOption {
        type = types.str;
        description = "Default rabbitmq user";
        default = "guest";
      };

      defaultPassword = mkSecretOption {
        description = "Default rabbitmq password";
        default.key = "password";
      };

      erlangCookie = mkSecretOption {
        description = "Rabbitmq erlang cookie secret";
        default.key = "cookie";
      };

      enabledPlugins = mkOption {
        description = "List of rabbitmq plugins";
        type = types.listOf types.str;
        default = ["rabbitmq_management"];
      };

      storage = {
        enable = mkOption {
          description = "Whether to enable persistent storage for rabbitmq";
          type = types.bool;
          default = false;
        };

        size = mkOption {
          description = "Storage size";
          type = types.str;
          default = "1000m";
        };

        class = mkOption {
          description = "Storage class";
          type = types.nullOr types.str;
          default = null;
        };
      };
    };

    config = {
      kubernetes.resources.statefulSets.rabbitmq = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          replicas = config.replicas;
          serviceName = "${module.name}-headless";
          template = {
            metadata.labels.app = module.name;
            metadata.annotations = {
              "prometheus.io/scrape" = "true";
              "prometheus.io/port" = "9090";
            };
            spec = {
              serviceAccountName = module.name;
              terminationGracePeriodSeconds = 10;
              initContainers.copy-config = {
                image = config.image;
                command = ["sh" "-c" "cp /config/* /etc/rabbitmq"];
                volumeMounts.config = {
                  name = "config";
                  mountPath = "/config";
                };
                volumeMounts.config-rw = {
                  name = "config-rw";
                  mountPath = "/etc/rabbitmq";
                };
              };
              containers.rabbitmq = {
                image = config.image;
                imagePullPolicy = "Always";
                env = {
                  RABBITMQ_DEFAULT_USER.value = config.defaultUser;
                  RABBITMQ_DEFAULT_PASS = secretToEnv config.defaultPassword;
                  RABBITMQ_ERLANG_COOKIE = secretToEnv config.erlangCookie;
                  NODE_NAME.valueFrom.fieldRef.fieldPath = "metadata.name";
                  RABBITMQ_NODENAME.value = "rabbit@$(NODE_NAME).${module.name}-headless.${module.namespace}.svc.cluster.local";
                  RABBITMQ_USE_LONGNAME.value = "true";
                };
                resources.requests = {
                  cpu = "200m";
                  memory = "512Mi";
                };
                volumeMounts.storage = mkIf config.storage.enable {
                  name = "storage";
                  mountPath = "/var/lib/rabbitmq";
                };
                volumeMounts.config-rw = {
                  name = "config-rw";
                  mountPath = "/etc/rabbitmq";
                };
                ports = [{
                  name = "http";
                  protocol = "TCP";
                  containerPort = 15672;
                } {
                  name = "amqp";
                  protocol = "TCP";
                  containerPort = 5672;
                }];
                livenessProbe = {
                  exec.command = ["rabbitmqctl" "status"];
                  initialDelaySeconds = 60;
                  periodSeconds = 60;
                  timeoutSeconds = 10;
                };
                readinessProbe = {
                  exec.command = ["rabbitmqctl" "status"];
                  initialDelaySeconds = 20;
                  periodSeconds = 60;
                  timeoutSeconds = 10;
                };
              };
              containers.rabbitmq-prom-exporter = {
                image = "kbudde/rabbitmq-exporter";
                env = {
                  RABBIT_PASSWORD = secretToEnv config.defaultPassword;
                  RABBIT_USER.value = config.defaultUser;
                };
                resources.requests = {
                  cpu = "50m";
                  memory = "50Mi";
                };
                ports = [{
                  name = "metrics";
                  containerPort = 9090;
                }];
              };
              volumes.config-rw.emptyDir = {};
              volumes.config.configMap.name = module.name;
            };
          };
          volumeClaimTemplates = mkIf config.storage.enable [{
            metadata.name = "storage";
            spec = {
              accessModes = ["ReadWriteOnce"];
              storageClassName = config.storage.class;
              resources.requests.storage = config.storage.size;
            };
          }];
        };
      };

      kubernetes.resources.services.rabbitmq-headless = {
        metadata.name = "${module.name}-headless";
        metadata.labels.app = module.name;
        spec = {
          selector.app = module.name;
          clusterIP = "None";
          ports = [{
            name = "amqp";
            protocol = "TCP";
            port = 5672;
            targetPort = 5672;
          }];
        };
      };

      kubernetes.resources.services.rabbitmq = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          selector.app = module.name;
          ports = [{
            name = "http";
            protocol = "TCP";
            port = 15672;
            targetPort = 15672;
          } {
            name = "amqp";
            protocol = "TCP";
            port = 5672;
            targetPort = 5672;
          }];
        };
      };

      kubernetes.resources.configMaps.rabbitmq = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        data.enabled_plugins = "[${concatStringsSep "," (config.enabledPlugins ++ ["rabbitmq_peer_discovery_k8s"])}].";
        data."rabbitmq.conf" = ''
          ## Cluster formation. See http://www.rabbitmq.com/cluster-formation.html to learn more.
          cluster_formation.peer_discovery_backend  = rabbit_peer_discovery_k8s
          cluster_formation.k8s.host = kubernetes.default.svc.cluster.local
          ## Should RabbitMQ node name be computed from the pod's hostname or IP address?
          ## IP addresses are not stable, so using [stable] hostnames is recommended when possible.
          ## Set to "hostname" to use pod hostnames.
          ## When this value is changed, so should the variable used to set the RABBITMQ_NODENAME
          ## environment variable.
          cluster_formation.k8s.address_type = hostname
          # overrides Kubernetes service name. Default value is "rabbitmq".
          cluster_formation.k8s.service_name = ${module.name}-headless
          cluster_formation.k8s.hostname_suffix = .${module.name}-headless.${module.namespace}.svc.cluster.local
          ## How often should node cleanup checks run?
          cluster_formation.node_cleanup.interval = 30
          ## Set to false if automatic removal of unknown/absent nodes
          ## is desired. This can be dangerous, see
          ##  * http://www.rabbitmq.com/cluster-formation.html#node-health-checks-and-cleanup
          ##  * https://groups.google.com/forum/#!msg/rabbitmq-users/wuOfzEywHXo/k8z_HWIkBgAJ
          cluster_formation.node_cleanup.only_log_warning = true
          cluster_partition_handling = autoheal
          ## See http://www.rabbitmq.com/ha.html#master-migration-data-locality
          queue_master_locator=min-masters
          ## See http://www.rabbitmq.com/access-control.html#loopback-users
          loopback_users.guest = false
        '';
      };

      kubernetes.resources.serviceAccounts.rabbitmq = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
      };

      kubernetes.resources.roles.rabbitmq = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        metadata.labels.app = module.name;
        rules = [{
          apiGroups = [""];
          resources = ["endpoints"];
          verbs = ["get"];
        }];
      };

      kubernetes.resources.roleBindings.rabbitmq = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        metadata.labels.app = module.name;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          name = module.name;
        };
        subjects = [{
          kind = "ServiceAccount";
          name = module.name;
        }];
      };
    };
  };
}
