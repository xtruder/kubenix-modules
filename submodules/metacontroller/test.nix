{ config, kubenix, pkgs, lib, ... }:

with lib;

{
  imports = [
    kubenix.modules.testing
    kubenix.modules.k8s
    kubenix.modules.docker

    ./module.nix
  ];

  test = {
    name = "compositecontroller-1-x";
    description = "Test for compositecontroller submodule";
    extraConfiguration = {
      services.kubernetes.kubelet.seedDockerImages = config.docker.export;
    };
  };

  submodules.imports = [
    ./1.x.nix
  ];

  docker.images.catset-controller.image = (pkgs.dockerTools.pullImage {
    imageName = "metacontroller/nodejs-server";
    imageDigest = "sha256:9cd51dc676a4f61e65e7be1c3b21924b4596415c9a5b0f19f51baedebf75eb9e";
    sha256 = "0aaw7994jgsnqm700hlcbhk4gib167vrwvyy03h30b7pfiwzn60z";
    finalImageTag = "0.2";
  }) // {
    imageName = "nodejs-server";
  };

  kubernetes.api.namespaces.test = {};

  kubernetes.customResources = [{
    group = "ctl.enisoc.com";
    version = "v1";
    kind = "CatSet";
    resource = "catsets";
    description = "CatSet controller";
    alias = "catsets";
  }];

  submodules.instances.metacontroller = {
    submodule = "metacontroller";
    config.kubernetes.namespace = "test";
  };

  kubernetes.api.customresourcedefinitions.catset = {
    metadata.name = "catsets.ctl.enisoc.com";
    spec = {
      group = "ctl.enisoc.com";
      version = "v1";
      scope = "Namespaced";
      names = {
        plural = "catsets";
        singular = "catset";
        kind = "CatSet";
        shortNames = ["cs"];
      };
      subresources.status = {};
    };
  };

  kubernetes.api.compositecontrollers.catset-contoller = {
    metadata.name = "catset-controller";
    metadata.namespace = "test";
    spec = {
      parentResource = {
        apiVersion = "ctl.enisoc.com/v1";
        resource = "catsets";
        revisionHistory.fieldPaths = ["spec.template"];
      };
      childResources = [{
        apiVersion = "v1";
        resource = "pods";
        updateStrategy = {
          method = "RollingRecreate";
          statusChecks.conditions = [{
            type = "Ready";
            status = "True";
          }];
        };
      } {
        apiVersion = "v1";
        resource = "persistentvolumeclaims";
      }];
      hooks = {
        sync.webhook.url = "http://catset-controller.test/sync";
        finalize.webhook.url = "http://catset-controller.test/sync";
      };
    };
  };

  kubernetes.api.deployments.catset-controller = {
    metadata.namespace = "test";
    spec = {
      replicas = 1;
      selector.matchLabels.app = "catset-controller";
      template = {
        metadata.labels.app = "catset-controller";
        spec = {
          containers.controller = {
            image = config.docker.images.catset-controller.path;
            imagePullPolicy = "Always";
            volumeMounts = [{
              name = "hooks";
              mountPath = "/node/hooks";
            }];
          };
          volumes.hooks.configMap.name = "catset-controller";
        };
      };
    };
  };

  kubernetes.api.configmaps.catset-controller = {
    metadata.namespace = "test";
    data."sync.js" = builtins.readFile ./sync.js;
  };

  kubernetes.api.services.catset-controller = {
    metadata.namespace = "test";
    spec = {
      selector.app = "catset-controller";
      ports = [{ port = 80; }];
    };
  };

  kubernetes.api.catsets.nginx-backend = {
    metadata.name = "nginx-backend";
    metadata.namespace = "test";
    spec = {
      serviceName = "nginx-backend";
      replicas = 2;
      selector.matchLabels.app = "nginx";
      template = {
        metadata.labels = {
          app = "nginx";
          component = "backend";
        };
        spec = {
          terminationGracePeriodSeconds = 1;
          containers = [{
            name = "nginx";
            image = "gcr.io/google_containers/nginx-slim:0.8";
            ports = [{
              containerPort = 80;
              name = "web";
            }];
          }];
        };
      };
    };
  };
}
