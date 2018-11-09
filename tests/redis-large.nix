{ config, k8s, ... }:

{
  require = import ../modules/module-list.nix;

  kubernetes.modules.redis = {
    configuration = {
      nodes.memory = 20480;
      storage.size = "30G";
    };
  };

  kubernetes.resources.jobs.fill-redis = {
    spec.template.spec.restartPolicy = "OnFailure";
    spec.template.spec.containers = [{
      name = "vulcan";
      image = "xtruder/vulcan";
      args = ["1000000" "set" "-h" "redis"];
    }];
  };
}
