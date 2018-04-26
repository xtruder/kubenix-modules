{ name, lib, config, k8s, ... }:

with lib;
with k8s;

{
  kubernetes.moduleDefinitions.rabbitmq.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Docker image to use";
        type = types.str;
        default = "xtruder/rabbitmq-autocluster:3.6.8-management";
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
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          replicas = config.replicas;
          serviceName = name;
          template = {
            metadata.labels.app = name;
            metadata.annotations = {
              "prometheus.io/scrape" = "true";
              "prometheus.io/port" = "9090";
            };
            spec = {
              serviceAccountName = name;
              terminationGracePeriodSeconds = 10;
              containers.rabbitmq = {
                image = config.image;
                imagePullPolicy = "Always";
                env = {
                  RABBITMQ_DEFAULT_USER.value = config.defaultUser;
                  RABBITMQ_DEFAULT_PASS = secretToEnv config.defaultPassword;
                  RABBITMQ_ERLANG_COOKIE = secretToEnv config.erlangCookie;
                  MY_POD_IP.valueFrom.fieldRef.fieldPath = "status.podIP";
                  RABBITMQ_USE_LONGNAME.value = "true";
                  RABBITMQ_NODENAME.value = "rabbit@$(MY_POD_IP)";
                  AUTOCLUSTER_TYPE.value = "k8s";
                  AUTOCLUSTER_DELAY.value = "10";
                  K8S_ADDRESS_TYPE.value = "ip";
                  AUTOCLUSTER_CLEANUP.value = "true";
                  CLEANUP_WARN_ONLY.value = "false";
                };
                resources.requests = {
                  cpu = "200m";
                  memory = "512Mi";
                };
                volumeMounts.storage = mkIf config.storage.enable {
                  name = "storage";
                  mountPath = "/var/lib/rabbitmq";
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
                  initialDelaySeconds = 30;
                  timeoutSeconds = 5;
                };
                readinessProbe = {
                  exec.command = ["rabbitmqctl" "status"];
                  initialDelaySeconds = 10;
                  timeoutSeconds = 5;
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

      kubernetes.resources.services.rabbitmq = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          selector.app = name;
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

      kubernetes.resources.serviceAccounts.rabbitmq = {
        metadata.name = name;
        metadata.labels.app = name;
      };

      kubernetes.resources.roles.rabbitmq = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = name;
        metadata.labels.app = name;
        rules = [{
          apiGroups = [""];
          resources = ["endpoints"];
          verbs = ["get"];
        }];
      };

      kubernetes.resources.roleBindings.rabbitmq = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = name;
        metadata.labels.app = name;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          name = name;
        };
        subjects = [{
          kind = "ServiceAccount";
          name = name;
        }];
      };
    };
  };
}
