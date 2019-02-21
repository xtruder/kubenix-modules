{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {

  };

  config = {
    submodule = {
      name = "etcd-operator";
      version = "1.0.0";
      description = "";
    };
  };
}