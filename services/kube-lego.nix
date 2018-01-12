{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.kube-lego.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "kube-lego image to use";
        type = types.str;
        default = "jetstack/kube-lego:0.1.5";
      };

      logLevel = mkOption {
        description = "kube-lego log level";
        type = types.str;
        default = "debug";
      };

      email = mkOption {
        description = "kube-lego letsencrypt email";
        example = "cert@example.com";
        type = types.str;
      };

      url = mkOption {
        description = "kube-lego letsencrypt url";
        type = types.str;
        default = "https://acme-v01.api.letsencrypt.org/directory";
      };
    };

    config = {
      kubernetes.resources.deployments.kube-lego = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          replicas = 1;
          selector.matchLabels.app = name;
          template = {
            metadata.labels.app = name;
            spec = {
              containers.kube-lego = {
                image = config.image;
                ports = [{
                  containerPort = 8080;
                }];
                env = {
                  LEGO_LOG_LEVEL.value = config.logLevel;
                  LEGO_EMAIL.value = config.email;
                  LEGO_URL.value = config.url;
                  LEGO_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                  LEGO_POD_IP.valueFrom.fieldRef.fieldPath = "status.podIP";
                };
                readinessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = 8080;
                  };
                  initialDelaySeconds = 5;
                  timeoutSeconds = 1;
                };
              };
            };
          };
        };
      };
    };
  };
}
