{ config, ... }:

let
  domain = "example.net";
  email = "user@example.com";
in {
  require = [
    ./test.nix
    ../modules/kube-lego.nix
    ../modules/nginx.nix
  ];

  kubernetes.modules.kube-lego = {
    module = "kube-lego";
    namespace = "kube-system";
    configuration.email = email;
  };

  kubernetes.resources.ingresses.test = {
    metadata.annotations = {
      "kubernetes.io/tls-acme" = "true";
      "kubernetes.io/ingress.class" = "gce";
    };
    spec = {
      tls = [{
        hosts = ["test.${domain}"];
        secretName = "test-tls";
      }];
      rules = [{
        host = "test.${domain}";
        http.paths = [{
          path = "/*";
          backend = {
            serviceName = "nginx";
            servicePort = 80;
          };
        }];
      }]; 
    };
  };

  kubernetes.modules.nginx = {
    module = "nginx";
    configuration.kubernetes.resources.services.nginx.spec.type = "NodePort";
  };
}
