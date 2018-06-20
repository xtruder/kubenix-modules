{ config, k8s, ... }:

{
  require = [
    ./test.nix
    ../modules/vault-ui.nix
    ../modules/vault-controller.nix
    ../modules/vault.nix
  ];

  kubernetes.modules.vault = {
    module = "vault";
    configuration.dev = {
      enable = true;
      token = {
        name = "vault-token";
        key = "token";
      };
    };
  };

  kubernetes.modules.vault-controller = {
    module = "vault-controller";
    configuration = {
      vault.address = "http://vault:8200";
      vault.token.name = "vault-token";
    };
  };

  kubernetes.modules.vault-ui = {};

  kubernetes.resources.secrets.vault-token.data = {
    token = k8s.toBase64 "e2bf6c5e-88cc-2046-755d-7ba0bdafef35";
  };

  kubernetes.modules.test-secret-claim = {
    module = "secret-claim";
    configuration.path = "tokens/test";
  };
}
