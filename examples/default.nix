{ pkgs
, kubenix
, images }:

let
  buildExample = example: extraOpts: kubenix.buildResources {
    configuration.imports = [example {
      _module.args.images = images;
    } extraOpts];
  };
in {
  vault-prod = buildExample ./vault/vault-prod.nix {};
  ca-deployer = buildExample ./deployer/ca-deployer.nix {};
  logs = buildExample ./logs {};
  nginx-ingress-external-dns = buildExample ./ingress/nginx-ingress-external-dns.nix {};
  prometheus = buildExample ./prometheus/default.nix {};
}
