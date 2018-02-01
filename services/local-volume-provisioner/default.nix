{ name, lib, config, k8s, ... }:

with lib;
with k8s;

{
  kubernetes.moduleDefinitions.local-volume-provisioner.module = {name, config, ...}: {
    options = {
      location = mkOption {
        description = "Location";
        type = types.str;
        default = "/mnt/disks";
      };
    };

    config = {
      kubernetes.resources.daemonSets.local-volume-provisioner = mkMerge [
        (loadYAML ./local-volume-provisioner-daemon-set.yaml)
        {
          metadata.name = name;
          metadata.labels.app = name;
          spec.template.spec.volumes.discovery-vol.hostPath.path = config.location;
          spec.selector.matchLabels.app = name;
          spec.template.metadata.labels.app = name;
        }
      ];

      kubernetes.resources.clusterRoleBindings.local-volume-provisioner-cluster-role-binding-node = mkMerge [
        (loadYAML ./local-volume-provisioner-cluster-role-binding-node.yaml)
        {
          metadata.name = "${name}-cluster-role-binding-node";
          metadata.labels.app = name;
        }
      ];

      kubernetes.resources.clusterRoleBindings.local-volume-provisioner-cluster-role-binding-pv = mkMerge [
        (loadYAML ./local-volume-provisioner-cluster-role-binding-pv.yaml)
        {
          metadata.name = "${name}-cluster-role-binding-pv";
          metadata.labels.app = name;
        }
      ];

      kubernetes.resources.serviceAccounts.local-volume-provisioner-service-account = mkMerge [
        (loadYAML ./local-volume-provisioner-service-account.yaml)
        {
          metadata.name = "${name}-service-account";
          metadata.labels.app = name;
        }
      ];
    };
  };
}
