{ config, k8s, ... }:

{
  require = import ../modules/module-list.nix;

  kubernetes.modules.redis = {
    module = "redis";
    configuration.password = {
      name = "redis";
      key = "password";
    };
  };

  kubernetes.resources.secrets.redis.data.password = k8s.toBase64 "test";
}
