{ config, k8s, ... }:

{
  require = [./test.nix ../modules/rabbitmq.nix];

  kubernetes.resources.secrets.rabbitmq.data = {
    password = k8s.toBase64 "rabbitmq";
    cookie = k8s.toBase64 "secret cookie here";
  };

  kubernetes.modules.rabbitmq = {
    module = "rabbitmq";
    configuration = {
      storage.enable = true;
      defaultPassword.name = "rabbitmq";
      erlangCookie.name = "rabbitmq";
    };
  };
}
