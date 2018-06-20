{ config, options, lib, ... }:

with lib;

{
  options.kubernetes.dockerRegistry = mkOption {
    description = "Default docker registry";
    type = types.str;
    default = "xtruder";
  };

  config.kubernetes.defaultModuleConfiguration.all = {
    options.kubernetes.dockerRegistry = options.kubernetes.dockerRegistry;
    config.kubernetes.dockerRegistry = config.kubernetes.dockerRegistry;
  };
}