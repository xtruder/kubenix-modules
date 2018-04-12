{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.resources.namespaces.test = {};

  kubernetes.modules.kubelog = {
    module = "kubelog";
    configuration = {
      outputConfig = ''
        stdout { codec => rubydebug }
      '';
    };
  };

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
