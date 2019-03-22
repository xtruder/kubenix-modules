{ config, pkgs, lib, kubenix, ... }:

with lib;

{
  imports = [ kubenix.modules.k8s ];

  config = {
    kubernetes.customResources = [{
      group = "metacontroller.k8s.io";
      version = "v1alpha1";
      kind = "CompositeController";
      resource = "compositecontrollers";
      description = "Composite controller";
      alias = "compositecontrollers";
      module.imports = [ ./compositecontroller.nix ];
    }];
  };
}
