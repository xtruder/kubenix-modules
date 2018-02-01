{ config, k8s, ... }:

{
  require = [../services/local-volume-provisioner];

  kubernetes.modules.local-volume-provisioner = {
    module = "local-volume-provisioner";
  };
}
