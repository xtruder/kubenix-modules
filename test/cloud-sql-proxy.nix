{ config, k8s, ... }:

with k8s;

{
  require = import ../services/module-list.nix;

  kubernetes.modules.cloud-sql-proxy = {
    module = "cloud-sql-proxy";

    configuration = {
      instanceCredentials = "file.json";
      dbCredentials = {
        username = {
          name = "mysql-user";
          key = "username";
        };
        password = {
          name = "mysql-user";
          key = "password";
        };
      };
    };
  };

  kubernetes.resources.secrets.mysql-user.data = {
    username = toBase64 "user";
    password = toBase64 "mypassword";
  };
}