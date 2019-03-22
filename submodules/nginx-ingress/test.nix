{ config, kubenix, lib, pkgs, ... }:

with lib;

{
  imports = [
    kubenix.modules.k8s
    kubenix.modules.docker
  ];

  test = {
    name = "nginx-ingress-controller-1-x";
    description = "Test for nginx ingress controller submodule";
    extraConfiguration = {
      environment.systemPackages = [ pkgs.curl ];
      services.kubernetes.kubelet.seedDockerImages = config.docker.export;
    };
    testScript = ''
      $kube->waitUntilSucceeds("kubectl apply -f ${toYAML config.kubernetes.generated}");
      $kube->waitUntilSucceeds("kubectl get deployment -o go-template nginx-ingress --template={{.status.readyReplicas}} | grep 2");
      $kube->waitUntilSucceeds("curl -H 'Host: test.example.com' http://nginx-ingress.default.svc.cluster.local | grep -i 'Welcome to nginx'");
    '';
  };

  submodules.imports = [
    ./1.x.nix
    ../nginx/1.x.nix
  ];

  docker.registry.url = mkForce "";

  submodules.instances.nginx-ingress = {
    submodule = "nginx-ingress-controller";
    args = {
      replicas = 2;
      electionId = "ingress-controller-lead-2";
      ingressClass = "mynginx";
      reportNodeInternalIpAddress = true;
      headers = {
        "X-Custom-Header" = "true";
      };
    };
  };

  submodules.instances.nginx = {
    submodule = "nginx";
  };

  kubernetes.api.ingresses.nginx-ingress = {
    metadata.annotations."kubernetes.io/ingress.class" = "mynginx";
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
