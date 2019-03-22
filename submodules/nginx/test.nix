{ config, kubenix, lib, pkgs, ... }:

with lib;

{
  imports = [
    kubenix.modules.k8s
    kubenix.modules.docker
  ];

  test = {
    name = "nginx-1-x";
    description = "Test for nginx submodule";
    extraConfiguration = {
      environment.systemPackages = [ pkgs.curl ];
      services.kubernetes.kubelet.seedDockerImages = config.docker.export;
    };
    testScript = ''
      $kube->waitUntilSucceeds("kubectl apply -f ${toYAML config.kubernetes.generated}");
      $kube->waitUntilSucceeds("kubectl get deployment -o go-template nginx --template={{.status.readyReplicas}} | grep 2");
      $kube->waitUntilSucceeds("curl http://nginx.default.svc.cluster.local");
    '';
  };

  submodules.imports = [
    ./1.x.nix
  ];

  docker.registry.url = mkForce "";

  submodules.instances.nginx = {
    submodule = "nginx";
    args.replicas = 2;
  };
}
