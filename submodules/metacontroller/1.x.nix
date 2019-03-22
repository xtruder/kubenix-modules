{ config, name, pkgs, lib, kubenix, submodule, ... }:

with lib;

let
  package = pkgs.callPackage ./package.nix { };
in {
  imports = [
    kubenix.modules.submodule
    kubenix.modules.k8s
    kubenix.modules.docker
  ];

  config = {
    submodule = {
      name = "metacontroller";
      version = "1.0.0";
      description = "Lightweight Kubernetes controllers as a service";
    };

    docker.images.metacontroller.image = pkgs.dockerTools.buildLayeredImage {
      name = "metacontroller";
      contents = [ package ];
      extraCommands = ''
        mkdir etc
        chmod u+w etc
        echo "nginx:x:1000:1000::/:" > etc/passwd
        echo "nginx:x:1000:app" > etc/group
      '';
      config = {
        Cmd = ["metacontroller.app"];
      };
    };

    kubernetes.api.serviceaccounts.metacontroller = {
      metadata.name = name;
      metadata.labels.app = name;
    };

    kubernetes.api.clusterroles.metacontroller = {
      metadata.name = name;
      metadata.labels.app = name;
      rules = [{
        apiGroups = ["*"];
        resources = ["*"];
        verbs = ["*"];
      }];
    };

    kubernetes.api.clusterrolebindings.metacontroller = {
      metadata.name = name;
      metadata.labels.app = name;
      subjects = [{
        kind = "ServiceAccount";
        name = name;
        namespace = config.kubernetes.namespace;
      }];
      roleRef = {
        kind = "ClusterRole";
        name = name;
        apiGroup = "rbac.authorization.k8s.io";
      };
    };

    kubernetes.api.clusterroles.aggregate-metacontroller-view = {
      metadata.name = name;
      metadata.labels= {
        app = name;
        "rbac.authorization.k8s.io/aggregate-to-admin" = "true";
        "rbac.authorization.k8s.io/aggregate-to-edit" = "true";
        "rbac.authorization.k8s.io/aggregate-to-view" = "true";
      };
      rules = [{
        apiGroups = ["metacontroller.k8s.io"];
        resources = [
          "compositecontrollers"
          "controllerrevisions"
          "decoratorcontrollers"
        ];
        verbs = [
          "get"
          "list"
          "watch"
        ];
      }];
    };

    kubernetes.api.clusterroles.aggregate-metacontroller-edit = {
      metadata.name = name;
      metadata.labels= {
        app = name;
        "rbac.authorization.k8s.io/aggregate-to-admin" = "true";
        "rbac.authorization.k8s.io/aggregate-to-edit" = "true";
      };
      rules = [{
        apiGroups = ["metacontroller.k8s.io"];
        resources = [
          "controllerrevisions"
        ];
        verbs = [
          "create"
          "delete"
          "deletecollection"
          "get"
          "list"
          "patch"
          "update"
          "watch"
        ];
      }];
    };

    kubernetes.api.statefulsets.metacontroller = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        replicas = 1;
        selector.matchLabels.app = name;
        serviceName = "";
        updateStrategy.type = "RollingUpdate";
        template = {
          metadata.labels.app = name;
          spec = {
            serviceAccountName = name; 
            containers.metacontroller = {
              image = config.docker.images.metacontroller.path;
              command = ["metacontroller.app"];
              args = ["--logtostderr" "-v=4" "--discovery-interval=20s"];
            };
          };
        };
      };
    };

    kubernetes.api.customresourcedefinitions.compositecontroller = {
      metadata.name = "compositecontrollers.metacontroller.k8s.io";
      spec = {
        group = "metacontroller.k8s.io";
        version = "v1alpha1";
        scope = "Cluster";
        names = {
          plural = "compositecontrollers";
          singular = "compositecontroller";
          kind = "CompositeController";
          shortNames = ["cc" "cctl"];
        };
      };
    };

    kubernetes.api.customresourcedefinitions.decoratorcontroller = {
      metadata.name = "decoratorcontrollers.metacontroller.k8s.io";
      spec = {
        group = "metacontroller.k8s.io";
        version = "v1alpha1";
        scope = "Cluster";
        names = {
          plural = "decoratorcontrollers";
          singular = "decoratorcontroller";
          kind = "DecoratorController";
          shortNames = ["dec" "decorators"];
        };
      };
    };

    kubernetes.api.customresourcedefinitions.controllerrevision = {
      metadata.name = "controllerrevisions.metacontroller.k8s.io";
      spec = {
        group = "metacontroller.k8s.io";
        version = "v1alpha1";
        scope = "Namespaced";
        names = {
          plural = "controllerrevisions";
          singular = "controllerrevision";
          kind = "ControllerRevision";
        };
      };
    };
  };
}
