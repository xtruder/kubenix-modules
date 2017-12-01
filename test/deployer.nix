{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.etcd-operator = {
    module = "etcd-operator";
  };

  kubernetes.modules.etcd = {
    module = "etcd-cluster";
    configuration.size = 1;
  };

  kubernetes.modules.galera = {
    module = "galera";

    configuration = {
      storage.enable = true;
      rootPassword = "root";
      replicas = 1;
    };
  };

  kubernetes.modules.mysql-databases = {
    module = "deployer";

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

      resource.mysql_user.fourstop.user = "fourstop";

      resource.mysql_grant.fourstop = {
        user = "fourstop";
        database = "fourstop";
        privileges = ["ALL"];
      };
    };
  };
}
