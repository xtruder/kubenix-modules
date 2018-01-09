{ name, lib, config, k8s, ... }:

with lib;
with k8s;

{
  kubernetes.moduleDefinitions.deployer.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Deployer image to use";
        type = types.str;
        default = "xtruder/deployer:latest";
      };

      exitOnError = mkOption {
        description = "Exit on error (do not atomatically retry)";
        type = types.bool;
        default = false;
      };

      preventDestroy = mkOption {
        description = "Prevent destroy (do not atomatically destroy resources)";
        type = types.bool;
        default = true;
      };

      configuration =  mkOption {
        description = "Terraform configuration";
        type = mkOptionType {
          name = "deepAttrs";
          description = "deep attribute set";
          check = isAttrs;
          merge = loc: foldl' (res: def: recursiveUpdate res def.value) {};
        };
        default = {};
      };
    };

    config = {
      kubernetes.resources.deployments.deployer = {
        metadata.name = name;
        metadata.labels.app = name;
        spec.template = {
          metadata.labels.app = name;
          spec = {
            containers.deployer = {
              image = config.image;
              env = {
                EXIT_ON_ERROR = mkIf config.exitOnError "1";
              };
              volumeMounts = [{
                name = "resources";
                mountPath = "/usr/local/deployer/inputs";
              }];
              resources = {
                requests.memory = "100Mi";
                requests.cpu = "100m";
              };
            };
            volumes.resources.configMap.name = name;
          };
        };
      };

      kubernetes.resources.configMaps.deployer = {
        metadata.name = name;
        data."main.tf.json" = builtins.toJSON
          (filterAttrs (n: v: v != [] && v != {}) config.configuration);
      };
    };
  };
}
