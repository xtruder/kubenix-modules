{ config, ... }:

{
  require = [../services/rabbitmq];

  kubernetes.modules.rabbitmq = {
    module = "rabbitmq";
    configuration.storage.enable = true;
  };
}
