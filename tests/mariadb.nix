{ config, k8s, ... }:

with k8s;

{
  require = [./test.nix ../modules/mariadb.nix];

  kubernetes.modules.mariadb = {
    module = "mariadb";

    configuration = {
      rootPassword.name = "mysql-root-password";
      args = ["log-bin-trust-function-creators"];
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

      initdb."init.sql" = ''
        create table if not exists test (text varchar(255) not null);
        insert into test(text) values("abcd");
      '';
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
