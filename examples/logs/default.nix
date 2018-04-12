{ config, ... }:

{
  require = import ../../services/module-list.nix;

  kubernetes.modules.kubelog = {
    module = "kubelog";
    configuration = {
      outputConfig = ''
        elasticsearch {
          hosts => "elasticsearch:9200"
          index => "logstash-v1-%{[kubernetes][replication_controller]}-%{+YYYY.MM.dd}"
        }
      '';
    };
  };

  kubernetes.modules.elasticsearch = {
    module = "elasticsearch";
    configuration.nodeSets = {
      master = {
        roles = ["master" "data" "ingest" "client"];
        replicas = 1;
        memory = 512;
      };
    };
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
          timestring = "%Y.%m.%d";
          unit = "days";
          unit_count = 30;
        }];
      }];
    };
  };

  kubernetes.resources.namespaces.test = {};
  kubernetes.resources.pods.echo.metadata.namespace = "test";
  kubernetes.resources.pods.echo.spec.containers.echo = {
    image = "busybox";
    command = ["sh" "-c" ''
      while true; do
        echo '{"message": "hello world"}'
        sleep 1
      done
    ''];
  };
}
