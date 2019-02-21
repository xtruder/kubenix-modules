{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
    image = mkOption {
      description = "Name of the zetcd image to use";
      type = types.str;
      default = "quay.io/coreos/zetcd";
    };

    replicas = mkOption {
      description = "Number of zetcd replicas";
      type = types.int;
      default = 3;
    };

    endpoints = mkOption {
      description = "Etcd endpoints";
      type = types.listOf types.str;
      default = ["etcd:2379"];
    };
  };

  config = {
    submodule = {
      name = "zetcd";
      version = "1.0.0";
      description = "";
    };
    kubernetes.api.deployments.zetcd = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        selector.matchLabels.app = name;
        template = {
          metadata.labels.app = name;
          spec = {
            containers.filebeat = {
              image = config.args.image;
              command = [
                "zetcd" "--zkaddr" "0.0.0.0:2181"
                "--endpoints" (concatStringsSep "," config.args.endpoints)
              ];

              resources.requests = {
                cpu = "100m";
                memory = "100Mi";
              };
            };
          };
        };
      };
    };

    kubernetes.api.services.zetcd = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        selector.app = name;
        ports = [{
          protocol = "TCP";
          port = 2181;
        }];
      };
    };
  };
}