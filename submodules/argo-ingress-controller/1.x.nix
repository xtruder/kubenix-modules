{ args, name, config, lib, pkgs, kubenix, ...}:

with lib;

{
  imports = [
    kubenix.modules.submodule
    kubenix.modules.k8s
    kubenix.modules.docker
  ];

  options.submodule.args = {
    replicas = mkOption {
      description = "Number of argo tunnel replicas to run";
      type = types.int;
      default = 3;
    };

    ingressClass = mkOption {
      description = "Ingress class for argo tunnel";
      type = types.str;
      default = "argo-tunnel";
    };

    extraArgs = mkOption {
      description = "Argo tunnel extra arguments";
      type = types.listOf types.str;
      default = [];
    };
  };

  config = {
    submodule = {
      name = "cloudflare-ingress-controller";
      version = "1.0.0";
      description = "Cloudflare argo ingress controller for Cloudflare's Argo Tunnels";
    };

    docker.images.argo-tunnel.image = pkgs.dockerTools.pullImage {
      imageName = "gcr.io/cloudflare-registry/argo-tunnel";
      imageDigest = "sha256:2a16697af42b55f3330a7872f61777298485539c3aad195a624bce0e81909cb5";
      sha256 = "13ml4dwia97jbb1bgva0z8fn8pb2a9sfc5v6nbwk6763zis3ajrb";
      finalImageTag = "0.6.5";
      finalImageName = "argo-tunnel";
    };

    kubernetes.api.deployments.argo-tunnel = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        selector.matchLabels.app = name;
        replicas = args.replicas;
        template = {
          metadata.name = name;
          metadata.labels.app = name;
          spec = {
            affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution = [{
              weight = 100;
              podAffinityTerm.labelSelector.matchExpressions = [{
                key = "app";
                operator = "In";
                values = [name];
              }];
              podAffinityTerm.topologyKey = "kubernetes.io/hostname";
            }];

            containers.argot = {
              image = config.docker.images.argo-tunnel.path;
              imagePullPolicy = "IfNotPresent";
              command = ["argot" "couple"];
              args = [
                "--incluster"
                "--ingress-class=${args.ingressClass}"
                "--v=3"
              ] ++ args.extraArgs;
              env.POD_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
              resources.requests = {
                cpu = "100m";
                memory = "128Mi";
              };
              resources.limits = {
                cpu = "100m";
                memory = "128Mi";
              };
            };
            serviceAccountName = name;
          };
        };
      };
    };

    kubernetes.api.serviceaccounts.argo-tunnel = {
      metadata.name = name;
      metadata.labels.app = name;
    };

    kubernetes.api.clusterroles.argo-tunnel = {
      metadata.name = name;
      metadata.labels.app = name;
      rules = [{
        apiGroups = ["" "extensions"];
        resources = ["ingresses" "services" "endpoints" "secrets"];
        verbs = ["list" "get" "watch"];
      }];
    };
      
    kubernetes.api.clusterrolebindings.argo-tunnel = {
      metadata.name = name;
      metadata.labels.app = name;

      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = name;
      };

      subjects = [{
        kind = "ServiceAccount";
        name = name;
        namespace = config.kubernetes.namespace;
      }];
    };
  };
}
