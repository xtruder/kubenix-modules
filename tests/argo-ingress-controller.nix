{ config, k8s, ... }:

with k8s;

{
  require = [
    ./test.nix
    ../modules/argo-ingress-controller.nix
    ../modules/nginx.nix
  ];

  kubernetes.modules.argo-ingress-controller = {
    module = "argo-ingress-controller";
  };

  kubernetes.modules.nginx = {
    module = "nginx";
  };

  kubernetes.resources.ingresses.nginx-ingress = {
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
