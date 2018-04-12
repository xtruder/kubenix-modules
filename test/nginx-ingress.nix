{ config, k8s, ... }:

with k8s;

{
  require = import ../services/module-list.nix;

  kubernetes.modules.nginx-ingress = {
    module = "nginx-ingress";
  };

  kubernetes.modules.nginx = {
    module = "nginx";
  };

  kubernetes.resources.ingresses.test-gatehub = {
    metadata.annotations."kubernetes.io/ingress.class" = "nginx";
    spec.rules = [{
      host = "test.gatehub.net";
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
