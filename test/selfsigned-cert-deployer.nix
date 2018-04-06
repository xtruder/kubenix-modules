{ config, k8s, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.selfsigned-cert-deployer.configuration = {
    secretName = "selfsigned-cert";
    dnsNames = ["test.example.com"];
  };
}
