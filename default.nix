{ pkgs ? import <nixpkgs> {}
, kubenix ? (
    if (builtins.tryEval (import <kubenix>)).success
    then import <kubenix>
    else import (builtins.fetchGit {
      url = "https://github.com/xtruder/kubenix.git";
    }
  )) { inherit pkgs; }
, images ? pkgs.callPackage ./images {}
}:

with pkgs.lib;

let
  globalConfig = {
    _module.args.images = images;
  };

  modules = import ./modules/module-list.nix ++ [globalConfig];

  tests = import ./tests {
    inherit pkgs kubenix images;
  };

  examples = import ./examples {
    inherit pkgs kubenix images;
  };
in {
  inherit images modules tests examples;

  # expose as services for backwards compatibillity
  services = modules;
}
