{ config, k8s, ... }:

with k8s;

{
  require = import ../services/module-list.nix;

  kubernetes.modules.galera = {
    module = "galera";

    configuration = {
      rootPassword.name = "mysql-root-password";
      mysql = {
        database = "test";
        user.name = "mysql-user";
        password.name = "mysql-user";
      };
      xtrabackupPassword.name = "mysql-xtrabackup-password";
      replicas = 3;
    };
  };

  kubernetes.modules.etcd-operator = {
    module = "etcd-operator";
  };

  kubernetes.modules.etcd = {
    module = "etcd-cluster";
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
