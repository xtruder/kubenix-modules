{ config, k8s, ... }:

{
  require = import ../modules/module-list.nix;

  kubernetes.modules.local-volume-provisioner = {
    module = "local-volume-provisioner";
  };
}
