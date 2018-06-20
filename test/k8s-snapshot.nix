{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.k8s-snapshot = {};

  kubernetes.resources.persistentVolumeClaims.myclaim = {
    metadata.annotations."backup.kubernetes.io/deltas" = "PT10M PT1H";
    spec.accessModes = ["ReadWriteOnce"];
    spec.resources.requests.storage = "10G";
  };
}
