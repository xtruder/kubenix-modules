{ config, kubenix, lib, ... }:

with lib;

{
  imports = [
    kubenix.modules.k8s
  ];

  test = {
    name = "cloudflare-ingress-controller-1-x";
    description = "Test for argo ingress controller submodule";
  };

  submodules.imports = [
    ./1.x.nix
  ];

  submodules.instances.argo-ingress-controller = {
    submodule = "cloudflare-ingress-controller";
  };

  kubernetes.api.ingresses.nginx-ingress = {
    metadata.annotations."kubernetes.io/ingress.class" = "argo-tunnel";
    spec.rules = [{
      host = "nginx.x-truder.net";
      http.paths = [{
        path = "/";
        backend = {
          serviceName = "nginx";
          servicePort = 80;
        };
      }];
    }];
  };
}
