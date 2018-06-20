{ config, k8s, ... }:

with k8s;

{
  require = [
    ./test.nix
    ../modules/nginx-ingress.nix
    ../modules/nginx.nix
  ];

  kubernetes.modules.nginx-ingress = {
    module = "nginx-ingress";
  };

  kubernetes.modules.nginx = {
    module = "nginx";
  };

  kubernetes.resources.ingresses.nginx-ingress = {
    metadata.annotations."kubernetes.io/ingress.class" = "nginx";
    spec.rules = [{
      host = "test.example.com";
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
