{ config, k8s, ... }:

with k8s;

{
  require = [./test.nix ../modules/mariadb.nix]
    ++ (import ../modules/prometheus/module-list.nix);

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
      initdb."init.sql" = ''
        create table if not exists transactions (value int not null, currency text not null);
        insert into transactions(value, currency) values(1, "eur");
        insert into transactions(value, currency) values(10, "eur");
        insert into transactions(value, currency) values(2, "usd");
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

  kubernetes.modules.prometheus-sql-exporter = {
    module = "prometheus-sql-exporter";

    configuration = {
      target.dataSourceName = "mysql://user:mypassword@tcp(mariadb:3306)/test";
      collectors.static_value.metrics = {
        max_transaction = {
          type = "gauge";
          help = "Transaction with max amount by currency";
          keyLabels = ["currency"];
          values = ["max_value"];
          query = ''
            select currency, max(value) as max_value from transactions
            group by currency
          '';
        };
      };
    };
  };
}
