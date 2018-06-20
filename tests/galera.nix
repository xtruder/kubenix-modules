{ config, k8s, ... }:

with k8s;

{
  require = [
    ./test.nix
    ../modules/galera.nix
    ../modules/etcd.nix
  ];

  kubernetes.modules.galera = {
    module = "galera";

    configuration = {
      rootPassword.name = "mysql-root-password";
      mysql = {
        database = "test";
        user.name = "mysql-user";
        user.key = "username";
        password.name = "mysql-user";
        password.key = "password";
      };
      xtrabackupPassword.name = "mysql-xtrabackup-password";
      replicas = 3;
    };
  };

  kubernetes.modules.etcd = {
    module = "etcd";
  };

  kubernetes.resources.secrets.mysql-user.data = {
    username = toBase64 "user";
    password = toBase64 "mypassword";
  };

  kubernetes.resources.secrets.mysql-root-password.data = {
    password = toBase64 "mypassword";
  };

  kubernetes.resources.secrets.mysql-xtrabackup-password.data = {
    password = toBase64 "mypassword";
  };
}
