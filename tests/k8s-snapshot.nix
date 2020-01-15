{ config, ... }:

{
  require = [ ./test.nix ../modules/k8s-snapshot.nix ];

  kubernetes.modules.k8s-snapshot = {
    configuration.gcloud.credentials = {
      name = "test";
      key = "test";
    };
  };

  kubernetes.modules.k8s-snapshot-rule.configuration = {
    deltas = ["P12D"];
    backend = "google";
    disk = {};
  };

  kubernetes.resources.persistentVolumeClaims.myclaim = {
    metadata.annotations."backup.kubernetes.io/deltas" = "PT10M PT1H";
    spec.accessModes = ["ReadWriteOnce"];
    spec.resources.requests.storage = "10G";
  };
}
