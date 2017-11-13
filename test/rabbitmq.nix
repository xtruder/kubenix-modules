{ config, ... }:

{
  require = import ../module-list.nix;

  kubernetes.modules.rabbitmq = {
    module = "rabbitmq";
    configuration.storage.enable = true;
  };
}
