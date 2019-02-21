{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
    image = mkOption {
      description = "Name of the locust image to use";
      type = types.str;
      default = "quay.io/honestbee/locust:0.7.5";
    };

    locustScript = mkOption {
      description = "Path to locus script";
      type = types.path;
    };

    targetHost = mkOption {
      description = "Target host";
      type = types.str;
    };

    tasks = mkOption {
      description = "Attribute set of locust tasks";
      type = types.attrsOf (types.either types.package types.str);
    };

    master = {
      extraConfig = mkOption {
        description = "Master configuration";
        type = types.attrsOf types.str;
        default = {};
        example = {
          target-host = "https://site.example.com";
        };
      };

      resources = {
        cpu = mkOption {
          description = "Requested CPU";
          type = types.str;
          default = "100m";
        };

        memory = mkOption {
          description = "Requested memory";
          type = types.str;
          default = "128Mi";
        };
      };
    };

    worker = {
      extraConfig = mkOption {
        description = "Worker configuration";
        type = types.attrsOf types.str;
        default = {};
      };

      replicas = mkOption {
        description = "Number of worker replicas to run";
        type = types.int;
        default = 2;
      };

      resources = {
        cpu = mkOption {
          description = "Requested CPU";
          type = types.str;
          default = "100m";
        };

        memory = mkOption {
          description = "Requested memory";
          type = types.str;
          default = "128Mi";
        };
      };
    };
  };

  config = {
    submodule = {
      name = "locust";
      version = "1.0.0";
      description = "";
    };
    kubernetes.api.deployments.locust-master = {
      metadata.name = "${name}-master";
      metadata.labels.app = name;
      metadata.labels.component = "master";
      spec = {
        replicas = 1;
        selector.matchLabels.app = name;
        selector.matchLabels.component = "master";
        template = {
          metadata.labels.app = name; 
          metadata.labels.component = "master";
          spec = {
            containers.locust = {
              image = config.args.image;
              resources = {
                requests = config.args.master.resources;
                limits = config.args.master.resources;
              };

              env = {
                LOCUST_MODE.value = "master";
                LOCUST_SCRIPT.value = config.args.locustScript;
                LOCUSTFILE_PATH.value = config.args.locustScript;
              } // mapAttrs' (key: value: let
                key' = replaceStrings ["-"] ["_"] (toUpper key);
              in nameValuePair key' {inherit value;}) config.args.master.extraConfig;

              ports = [{
                name = "loc-master-web";
                containerPort = 8089;
              } {
                name = "loc-master-p1";
                containerPort = 5557;
              } {
                name = "loc-master-p2";
                containerPort = 5558;
              }];

              volumeMounts = [{
                name = "locust-tasks";
                mountPath = "/locust-tasks/";
              }];

              livenessProbe = {
                periodSeconds = 30;
                httpGet = {
                  path = "/";
                  port = 8089;
                };
              };

              readinessProbe = {
                periodSeconds = 30;
                httpGet = {
                  path = "/";
                  port = 8089;
                };
              };
            };

            volumes."locust-tasks".configMap.name = name;
            restartPolicy = "Always";
          };
        };
      };
    };

    kubernetes.api.deployments.locust-worker = {
      metadata.name = "${name}-worker";
      metadata.labels.app = name;
      metadata.labels.component = "worker";
      spec = {
        replicas = config.args.worker.replicas;
        selector.matchLabels.app = name;
        selector.matchLabels.component = "worker";
        template = {
          metadata.labels.app = name; 
          metadata.labels.component = "worker";
          spec = {
            containers.locust = {
              image = config.args.image;
              resources = {
                requests = config.args.worker.resources;
                limits = config.args.worker.resources;
              };

              env = {
                LOCUST_MODE.value = "worker";
                LOCUST_MASTER.value = name;
                LOCUST_MASTER_WEB.value = "8089";
                TARGET_HOST.value = config.args.targetHost;
                LOCUST_SCRIPT.value = config.args.locustScript;
                LOCUSTFILE_PATH.value = config.args.locustScript;
              } // mapAttrs' (key: value: let
                key' = replaceStrings ["-"] ["_"] (toUpper key);
              in nameValuePair key' {inherit value;}) config.args.worker.extraConfig;

              volumeMounts = [{
                name = "locust-tasks";
                mountPath = "/locust-tasks/";
              }];
            };

            volumes."locust-tasks".configMap.name = name;
            restartPolicy = "Always";
          };
        };
      };
    };

    kubernetes.api.configmaps.locust = {
      metadata.name = name;
      metadata.labels.app = name;
      data = mapAttrs (name: task:
        if isAttrs task then builtins.readFile task
        else task
      ) config.tasks;
    };

    kubernetes.api.services.locust = {
      metadata.name = name;
      metadata.labels.app = name;
      metadata.labels.component = "master";
      spec = {
        ports = [{
          port = 8089;
          name = "web";
        } {
          port = 5557;
          name = "master-p1";
        } {
          port = 5558;
          name = "master-p2";
        }];
        selector.app = name;
        selector.component = "master";
      };
    };
  };
}