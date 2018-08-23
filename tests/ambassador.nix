{ config, k8s, ... }:

with k8s;

{
  require = [
    ./test.nix
    ../modules/ambassador.nix
  ];

  kubernetes.modules.ambassador = {
    module = "ambassador";
  };
}
