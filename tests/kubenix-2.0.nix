{ pkgs
, kubenix
, images }:

let
  buildTest2 = test: extraOpts: kubenix.evalModules {
    modules = [
      test
      {
        _module.args.images = images;
      }
      extraOpts
    ];
  };
in {
  bitcoind = buildTest ./bitcoind.nix {};
}
