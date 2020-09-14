{ config, kubenix, lib, pkgs, ... }:

with lib;

{
  imports = [
    kubenix.modules.k8s
    kubenix.modules.docker
  ];

  test = {
    name = "elasticsearch-1-x";
    description = "Test for elasticsearch submodule";
    extraConfiguration = {
      environment.systemPackages = [ pkgs.curl ];
      services.kubernetes.kubelet.seedDockerImages = config.docker.export;
    };
    testScript = ''
      $kube->waitUntilSucceeds("kubectl apply -f ${toYAML config.kubernetes.generated}");
    '';
  };

  submodules.imports = [
    ./1.x.nix
  ];

  #docker.registry.url = mkForce "";

  submodules.instances.elasticsearch = {
    submodule = "elasticsearch";
    args.plugins = ["repository-s3" "repository-gcs"];
    args.storage.enable = false;
  };
}
