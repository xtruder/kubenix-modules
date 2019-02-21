{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
    image = mkOption {
      description = "Name of the minio image to use";
      type = types.str;
      default = "minio/minio";
    };

    replicas = mkOption {
      description = "Number of minio replicas to run";
      type = types.int;
      default = 4;
    };
    
    accessKey = mkSecretOption {
      description = "Minio access key";
      default.key = "accesskey";
    };

    secretKey = mkSecretOption {
      description = "Minio secret key";
      default.key = "secretkey";
    };

    configuration = mkOption {
      description = "Minio config";
      type = mkOptionType {
        name = "deepAttrs";
        description = "deep attribute set";
        check = isAttrs;
        merge = loc: foldl' (res: def: recursiveUpdate res def.value) {};
      };
    };

    storage = {
      size = mkOption {
        description = "Storage size";
        type = types.str;
        default = "10Gi";
      };

      class = mkOption {
        description = "Strage class";
        type = types.nullOr types.str;
        default = null;
      };
    };
  };

  config = {
    submodule = {
      name = "minio";
      version = "1.0.0";
      description = "";
    };
    configuration = {
      version = "20";
      region = "us-east-1";
      browser = "on";
      domain = "";
      logger = {
        console.enable = true;
        file = {
          enable = false;
          fileName = "";
        };
      };
      credential = {
        accessKey = "";
        secretKey = "";
      };
      notify.amqp."1" = {
        enable = false;
        url = "";
        exchange = "";
        routingKey = "";
        exchangeType = "";
        deliveryMode = 0;
        mandatory = false;
        immediate = false;
        durable = false;
        internal = false;
        noWait = false;
        autoDeleted = false;
      };
      notify.nats."1" = {
        enable = false;
        address = "";
        subject = "";
        username = "";
        password = "";
        token = "";
        secure = false;
        pingInterval = 0;
        streaming = {
          enable = false;
          clusterID = "";
          clientID = "";
          async = false;
          maxPubAcksInflight = 0;
        };
      };
      notify.elasticsearch."1" = {
        enable = false;
        format = "namespace";
        url = "";
        index = "";
      };
      notify.redis."1" = {
        enable = false;
        format = "namespace";
        address = "";
        password = "";
        key = "";
      };
      notify.postgresql."1" = {
        enable = false;
        format = "namespace";
        connectionString = "";
        table = "";
        host = "";
        port = "";
        user = "";
        password = "";
        database = "";
      };
      notify.kafka."1" = {
        enable = false;
        brokers = ["kafka:9092"];
        topic = "bucketevents";
      };
      notify.webhook."1" = {
        enable = false;
        endpoint = "";
      };
      notify.mysql."1" = {
        enable = false;
        format = "namespace";
        dsnString = "";
        table = "";
        host = "";
        port = "";
        password = "";
        database = "";
      };
      notify.mqtt."1" = {
        enable = false;
        broker = "";
        topic = "";
        qos = 0;
        clientId = "";
        username = "";
        password = "";
      };
    };

    kubernetes.api.configmaps.minio-config = {
      metadata.name = "${name}-config";
      metadata.labels.app = name;
      data."config.json" = builtins.toJSON config.args.configuration;
    };

    kubernetes.api.services.minio = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        clusterIP = "None";
        ports = [{
          name = "service";
          port = 9000;
          targetPort = 9000;
          protocol = "TCP";
        }];
        selector.app = name;
      };
    };

    kubernetes.api.statefulsets.minio = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        serviceName = name;
        replicas = config.args.replicas;
        selector.matchLabels.app = name;
        podManagementPolicy = "Parallel";
        template = {
          metadata.name = name;
          metadata.labels.app = name;
          metadata.annotations = {
            "prometheus.io/scrape" = "true";
            "prometheus.io/port" = "9290";
          };
          spec = {
            volumes = {
              minio-server-config.configMap.name = "${name}-config";
              podinfo.downwardAPI.items = [{
                path = "labels";
                fieldRef.fieldPath = "metadata.labels";
              }];
            };
            #containers.metrics = {
              #image = "joepll/minio-exporter";
              #imagePullPolicy = "Always";
              #args = ["-minio.bucket-stats"];
              #env = {
                #MINIO_URL.value = "http://localhost:9000";
                #MINIO_ACCESS_KEY = secretToEnv config.args.accessKey;
                #MINIO_SECRET_KEY = secretToEnv config.args.secretKey;
              #};
              #ports = [{
                #name = "metrics";
                #containerPort = 9290;
              #}];
            #};
            containers.minio = {
              image = config.args.image;
              imagePullPolicy = "Always";
              args = ["server"]
              ++ (if (config.args.replicas > 1)
                  then (
                    map (i: "http://${name}-${toString i}.${name}/export")
                      (range 0 (config.args.replicas - 1)))
                  else ["/export"]);
              volumeMounts = {
                export = {
                  name = "export";
                  mountPath = "/export";
                };
                minio-server-config = {
                  name = "minio-server-config";
                  mountPath = "/root/.minio";
                };
                podinfo = {
                  name = "podinfo";
                  mountPath = "/podinfo";
                  readOnly = false;
                };
              };
              ports = [{
                name = "service";
                containerPort = 9000;
              }];
              env = {
                MINIO_ACCESS_KEY = secretToEnv config.args.accessKey;
                MINIO_SECRET_KEY = secretToEnv config.args.secretKey;
              };
              resources.requests = {
                memory = "256Mi";
                cpu = "250m";
              };
            };
          };
        };
        volumeClaimTemplates = [{
          metadata.name = "export";
          spec = {
            accessModes = ["ReadWriteOnce"];
            resources.requests.storage = config.args.storage.size;
            storageClassName = mkIf (config.args.storage.class != null) config.args.storage.class;
          };
        }];
      };
    };
  };
}