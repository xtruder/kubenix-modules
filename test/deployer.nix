{ config, k8s, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.mariadb = {
    module = "mariadb";
    configuration.rootPassword.name = "mysql";
  };

  kubernetes.resources.secrets.mysql.data.password = k8s.toBase64 "root";

  kubernetes.modules.mysql-databases = {
    module = "deployer";

    configuration.vars = {
      MYSQL_ROOT_PASSWORD.value = "root";
    };
    configuration.configuration = {
      provider.mysql = {
        endpoint = "mariadb:3306";
        username = "root";
        password = "root";
      };

      resource.mysql_database.fourstop = {
        name = "fourstop";
        default_collation = "utf8_unicode_ci";
      };
    };
  };
}
