{ config, ... }:

{
  require = [
    ./test.nix
    ../modules/elasticsearch.nix
    ../modules/elasticsearch-curator.nix
  ];

  kubernetes.modules.elasticsearch = {
    module = "elasticsearch";
    configuration.plugins = ["repository-s3"];
  };

  kubernetes.modules.elasticsearch-curator = {
    module = "elasticsearch-curator";
    configuration = {
      hosts = ["elasticsearch"];
      port = 9200;
      actions = [{
        action = "close";
        description = "Close logstash indices older than 30 days";
        options.delete_aliases = true;
        filters = [{
          filtertype = "pattern";
          kind = "prefix";
          value = "logstash-*";
        } {
          filtertype = "age";
          source = "name";
          direction = "older";
          timestamp = "%Y.%m.%d";
          unit = "days";
          unit_count = 30;
        }];
      }];
    };
  };
}
