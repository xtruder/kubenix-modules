{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
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
    submodule = {
      name = "kube-lego";
      version = "1.0.0";
      description = "";
    };
    kubernetes.api.deployments.kube-lego = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        replicas = 1;
        selector.matchLabels.app = name;
        template = {
          metadata.labels.app = name;
          spec = {
            containers.kube-lego = {
              image = config.args.image;
              ports = [{
                containerPort = 8080;
              }];
              env = {
                LEGO_LOG_LEVEL.value = config.args.logLevel;
                LEGO_EMAIL.value = config.args.email;
                LEGO_URL.value = config.args.url;
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
}