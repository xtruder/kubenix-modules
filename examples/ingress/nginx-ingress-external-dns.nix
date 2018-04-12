{ config, k8s, ... }:

with k8s;

let
  namespace = "external-dns-test";
in {
  require = import ../../services/module-list.nix;

  kubernetes.resources.namespaces.${namespace} = {};

  kubernetes.modules.nginx-ingress = {
    inherit namespace;

    module = "nginx-ingress";
  };

  kubernetes.modules.nginx = {
    inherit namespace;

    module = "nginx";

    # if you want your ingress to be internal
    #configuration.kubernetes.resources.services.nginx = {
      #metadata.annotations."cloud.google.com/load-balancer-type" = "Internal";
    #};
  };

  kubernetes.modules.external-dns = {
    inherit namespace;

    module = "external-dns";

    configuration = {
      domainFilter = "external-dns-test.example.com";
      annotationFilter = "kubernetes.io/ingress.class=nginx";
      google.project = "example-dot-com";
      google.credentials = {
        name = "gcloud-credentials";
        key = "gcloud_credentials.json";
      };
    };
  };

  kubernetes.resources.ingresses.test-example = {
    metadata.namespace = namespace;
    metadata.annotations."kubernetes.io/ingress.class" = "nginx";
    spec.rules = [{
      host = "nginx.external-dns-test.example.com";
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
