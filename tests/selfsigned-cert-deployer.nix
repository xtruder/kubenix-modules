{ config, k8s, ... }:

{
  require = [./test.nix ../modules/selfsigned-cert-deployer.nix];

  kubernetes.modules.selfsigned-cert-deployer.configuration = {
    secretName = "selfsigned-cert";
    dnsNames = ["test.example.com"];
  };
}
