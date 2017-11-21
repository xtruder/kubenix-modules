{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.galera = {
    module = "galera";

    configuration = {
      storage.enable = true;
      rootPassword = "root";
      replicas = 3;
      user = "foo";
      database = "bar";
      password = "foobar";
    };
  };
}
