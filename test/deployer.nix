{ config, k8s, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.etcd = {
    module = "etcd";
  };

  kubernetes.modules.galera = {
    module = "galera";

    configuration = {
      rootPassword.name = "mysql";
      xtrabackupPassword.name = "mysql";
    };
  };

  kubernetes.resources.secrets.mysql.data.password = k8s.toBase64 "root";

  kubernetes.modules.mysql-databases = {
    module = "deployer";

    configuration.vars = {
      MYSQL_ROOT_PASSWORD.value = "root";
    };
    configuration.configuration = {
      provider.mysql = {
        endpoint = "galera:3306";
        username = "root";
        password = "root";
      };

      terraform.backend.etcdv3 = {
        endpoints = ["http://etcd:2379"];
        prefix = "terraform-state/";
        lock = true;
      };

      resource.mysql_database.fourstop = {
        name = "fourstop";
        default_collation = "utf8_unicode_ci";
      };
    };
  };
}
