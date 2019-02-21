{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
    name = mkOption {
      description = "Name of the secret claim";
      type = types.str;
      default = name;
    };

    type = mkOption {
      description = "Type of the secret";
      type = types.enum ["Opaque" "kubernetes.io/tls"];
      default = "Opaque";
    };

    path = mkOption {
      description = "Secret path";
      type = types.str;
    };

    renew = mkOption {
      description = "Renew time in seconds";
      type = types.nullOr types.int;
      default = null;
    };

    data = mkOption {
      type = types.nullOr types.attrs;
      description = "Data to pass to get secrets";
      default = null;
    };
  };

  config = {
    submodule = {
      name = "vault-controller";
      version = "1.0.0";
      description = "";
    };
    
  };
}