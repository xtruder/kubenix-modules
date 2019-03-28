{ config, k8s, ... }:

with k8s;

{
  require = [./test.nix ../modules/mariadb.nix ../modules/ghost.nix];

  kubernetes.modules.ghost = {
    module = "ghost";

    configuration = {
      url = "http://ghost.default.svc.cluster.local";
      database = {
        type = "mysql";
        name = "ghost";
        host = "mariadb.default";
        username = {
          name = "mysql-user";
          key = "username";
        };
        password = {
          name = "mysql-user";
          key = "password";
        };
      };
      storage.size = "1Gi";
    };
  };

  kubernetes.modules.mariadb = {
    module = "mariadb";

    configuration = {
      rootPassword.name = "mysql-root-password";
      mysql = {
        database = "ghost";
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
    username = toBase64 "ghost";
    password = toBase64 "ghost";
  };

  kubernetes.resources.secrets.mysql-root-password.data = {
    password = toBase64 "rootroot";
  };
}
