{ config, k8s, ... }:

with k8s;

{
  require = import ../services/module-list.nix;

  kubernetes.modules.mariadb = {
    module = "mariadb";

    configuration = {
      rootPassword.name = "mysql-root-password";
      mysql = {
        database = "test";
        user = {
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

  kubernetes.resources.secrets.mysql-root-password.data = {
    password = toBase64 "mypassword";
  };
}
