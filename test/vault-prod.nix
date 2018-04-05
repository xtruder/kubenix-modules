{ config, k8s, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.vault = {
    module = "vault";
    configuration = {
      configuration.storage.inmem = {};
      tls.additionalDomains = ["vault.example.com"];
    };
  };
}
