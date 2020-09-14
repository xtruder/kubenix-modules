{ config, lib, pkgs, name, kubenix, k8s, ...}:

with lib;
with k8s;

let
  args = config.submodule.args;

  esMajorVersion = head (builtins.splitVersion args.package.version);

  es6 = builtins.compareVersions args.package.version "6" >= 0;

  esPlugins = pkgs.buildEnv {
    name = "elasticsearch-plugins";
    paths = map (p:
      if isDerivation p then p
      else 
        if hasAttr p pkgs."elasticsearchPlugins${esMajorVersion}"
        then pkgs."elasticsearchPlugins${esMajorVersion}".${p}
        else throw "invalid elasticsearch plugin ${p} for es version ${args.package.version}"
    ) args.plugins;
  };

  dataDir = "/var/lib/elasticsearch";
in {
  imports = [
    kubenix.modules.submodule
    kubenix.modules.k8s
    kubenix.modules.docker
  ];

  options.submodule.args = {
    clusterName = mkOption {
      description = "Name of the elasticsearch cluster";
      type = types.str;
      default = name;
    };

    replicas = mkOption {
      description = "Number of replicas to run";
      type = types.int;
      default = 1;
    };

    package = mkOption {
      description = "Elasticsearch package to use.";
      type = types.package;
      default = pkgs.elasticsearch-oss;
    };

    plugins = mkOption {
      description = "Elasticsearch plugins to enable.";
      type = types.listOf (types.either types.str types.package);
      default = [];
      example = ["repository-s3" "repository-s3"];
    };

    jvmOptions = mkOption {
      description = "Elasticsearch jvm options";
      type = types.lines;
      default = optionalString es6 (builtins.readFile "${args.package}/config/jvm.options");
    };

    logging = mkOption {
      description = "Elasticsearch logging configuration.";
      type = types.lines;
      default = ''
        logger.action.name = org.elasticsearch.action
        logger.action.level = info
        appender.console.type = Console
        appender.console.name = console
        appender.console.layout.type = PatternLayout
        appender.console.layout.pattern = [%d{ISO8601}][%-5p][%-25c{1.}] %marker%m%n
        rootLogger.level = info
        rootLogger.appenderRef.console.ref = console
      '';
    };

    extraCmdLineOptions = mkOption {
      description = "Extra command line options for elasticsearch launcher";
      default = [];
      type = types.listOf types.str;
    };

    extraJavaOptions = mkOption {
      description = "Extra command line options for java";
      default = [];
      type = types.listOf types.str;
      example = ["-Djava.net.preferIPv4Stack=true"];
    };

    configuration = mkOption {
      description = "Elasticsearch configuration";
      default = {};
      type = mkOptionType {
        name = "deepAttrs";
        description = "deep attribute set";
        check = isAttrs;
        merge = loc: foldl' (res: def: recursiveUpdate res def.value) {};
      };
    };

    discoveryService = mkOption {
      description = "Name of the discovery service";
      type = types.str;
      default = "${name}-discovery";
    };

    minimumMasterNodes = mkOption {
      description = "Minium amount of master nodes";
      type = types.int;
      default = 1;
    };

    enableHttp = mkOption {
      description = "Whether to enable http on node";
      type = types.bool;
      default = true;
    };

    node = {
      master = mkOption {
        description = "Whether to make node eligible as master node";
        type = types.bool;
        default = true;
      };

      data = mkOption {
        description = "Whether to make node eligible as data node";
        type = types.bool;
        default = true;
      };
 
      ingest = mkOption {
        description = "Whether to make node eligible as ingest node";
        type = types.bool;
        default = true;
      }; 
    };

    storage = {
      enable = mkOption {
        description = "Whether to enable peristent storage";
        default = true;
        type = types.bool;
      };

      size = mkOption {
        description = "Elasticsearch storage size";
        type = types.str;
        default = "10Gi";
      };

      class = mkOption {
        description = "Elasticsearch storage class";
        type = types.str;
        default = "default";
      };
    };
  };

  config = {
    submodule = {
      name = "elasticsearch";
      version = "1.0.0";
      description = "Elasticsearch submodule";
    };

    submodule.args.configuration = {
      http.enabled = args.enableHttp;
      node.master = args.node.master;
      node.data = args.node.data;
      node.ingest = args.node.ingest;
      discovery.zen = {
        minimum_master_nodes = args.minimumMasterNodes;
        ping.unicast.hosts = args.discoveryService;
      };
    };

    docker.images.busybox.image = pkgs.dockerTools.buildLayeredImage {
      name = "busybox";
      contents = [ pkgs.busybox ];
    };

    docker.images.elasticsearch.image = pkgs.dockerTools.buildLayeredImage {
      name = "elasticsearch";
      contents = [ pkgs.elasticsearch esPlugins ];
      extraCommands = ''
        mkdir -p etc
        chmod u+w etc
        echo "elasticsearch:x:1000:1000::/:" > etc/passwd
        echo "elasticsearch:x:1000:elasticsearch" > etc/group
      '';
    };

    kubernetes.api.statefulsets.elasticsearch = {
      metadata = {
        name = name;
        labels.app = name;
      };
      spec = {
        replicas = args.replicas;
        serviceName = args.discoveryService;
        selector.matchLabels.app = name;
        template = {
          metadata.labels.app = name;
          spec = {
            securityContext.fsGroup = 1000;

            initContainers = [{
              name = "init-sysctl";
              image = config.docker.images.busybox.path;
              imagePullPolicy = "IfNotPresent";
              command = ["sysctl" "-w" "vm.max_map_count=262144"];
              securityContext.privileged = true;
            } {
              name = "copy-plugins";
              image = config.docker.images.busybox.path;
              imagePullPolicy = "IfNotPresent";
              command = ["sh" "-c" ''
                set -e

                # copy plugins
                rm -rf ${dataDir}/{plugins,lib,modules} || true
                cp -R /{plugins,lib,modules} ${dataDir}
                chmod +w ${dataDir}/{plugins,lib,modules,config,config/scripts}
              ''];
              volumeMounts = [{
                name = "storage";
                mountPath = dataDir;
              }];
            }];

            containers.elasticsearch = {
              image = config.docker.images.elasticsearch.path;
              imagePullPolicy = "IfNotPresent";
              command = ["/bin/elasticsearch"] ++ args.extraCmdLineOptions;
              env = {
                ES_HOME.value = dataDir;
                ES_JAVA_OPTS.value =
                  toString ( optional (!es6) [ "-Des.path.conf=${dataDir}/config"  ] ++ args.extraJavaOptions);
                ES_PATH_CONF = mkIf es6 { value = "${dataDir}/config"; };
              };
              securityContext = {
                privileged = false;
                capabilities.add = ["IPC_LOCK" "SYS_RESOURCE"];
              };
              volumeMounts = [{
                name = "storage";
                mountPath = dataDir;
              } {
                name = "config";
                mountPath = dataDir + "/config/elasticsearch.yml";
                subPath = "elasticsearch.yml";
                readOnly = false;
              } {
                name = "config";
                mountPath = dataDir + "/logging/log4j2.properties";
                subPath = "log4j2.properties";
                readOnly = false;
              } {
                name = "config";
                mountPath = dataDir + "/config/jvm.options";
                subPath = "jvm.options";
                readOnly = false;
              }];
            };

            volumes.storage = mkIf (!args.storage.enable) {
              emptyDir = {};
            };
            volumes.config = {
              configMap.name = name;
            };
          };
        };
        volumeClaimTemplates = mkIf args.storage.enable [{
          metadata.name = "storage";
          spec = {
            accessModes = ["ReadWriteOnce"];
            resources.requests.storage = args.storage.size;
            storageClassName = args.storage.class;
          };
        }];
      };
    };

    kubernetes.api.configmaps.elasticsearch = {
      metadata.name = name;
      metadata.labels.app = name;
      data."elasticsearch.yml" = generators.toYAML {} args.configuration;
      data."log4j2.properties" = args.logging;
      data."jvm.options" = args.jvmOptions;
    };
  };
}
