{ config, ... }:

{
  require = [./test.nix ../modules/elasticsearch.nix];

  kubernetes.modules.elasticsearch = {
    module = "elasticsearch";
    configuration.plugins = ["repository-s3"];
  };

  kubernetes.modules.elasticsearch-cluster = {
    module = "elasticsearch";
    configuration.name = "escluster";
    configuration.plugins = ["repository-s3"];
    configuration.nodeSets = {
      master = {
        roles = ["master"];
        replicas = 3;
      };

      client = {
        roles = ["client"];
        replicas = 2;
      };

      data = {
        roles = ["data"];
        replicas = 2;
        storage.enable = true;
      };
    };
  };
}
