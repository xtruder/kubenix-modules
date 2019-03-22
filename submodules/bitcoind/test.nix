
{ config, kubenix, lib, pkgs, ... }:

with lib;

{
  imports = [
    kubenix.modules.k8s
    kubenix.modules.docker
  ];

  test = {
    name = "bitcoind-1-x";
    description = "Test for nginx submodule";
    extraConfiguration = {
      environment.systemPackages = [ pkgs.curl ];
      services.kubernetes.kubelet.seedDockerImages = config.docker.export;
      services.kubernetes.addons.local-path-provisioner.enable = true;
    };
    testScript = ''
      $kube->waitUntilSucceeds("kubectl apply -f ${toYAML config.kubernetes.generated}");
      $kube->waitUntilSucceeds("curl http://bitcoind.default.svc.cluster.local:8332 | grep JSONRPC");
    '';
  };

  submodules.imports = [
    ./1.x.nix
  ];

  docker.registry.url = mkForce "";

  submodules.instances.bitcoind = {
    submodule = "bitcoind";
    args.rpcAuth = "test:a7d424b74122e17362e404ec5c5e6d$822c00a871d66c16b7a8ebcc7189624a74e4c2d46e31993012d1d36ade576363";
    config.kubernetes.api.statefulsets.bitcoind.spec.template.spec.containers.bitcoind.resources = {
      requests.memory = mkForce "512Mi";
      limits.memory = mkForce "512Mi";
    };
  };
}
