{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.kubelog = {
    module = "kubelog";

    configuration = {
      namespaces = ["default"];
      outputConfig = ''
        stdout { codec => rubydebug }
      '';
    };
  };

  kubernetes.resources.pods.echo.spec.containers.echo = {
    image = "busybox";
    command = ["sh" "-c" ''
      while true; do
        echo "hello world"
        sleep 1
      done
    ''];
  };
}