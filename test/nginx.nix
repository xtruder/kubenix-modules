{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.nginx-default = {
    module = "nginx";
  };

  kubernetes.modules.nginx = {
    module = "nginx";

    configuration.configuration = ''
      worker_processes  1;

      events {
          worker_connections  1024;
      }

      http {
        server {
          listen       80;

          error_log   stderr;
          access_log  /dev/stdout;

          location / {
            stub_status on;
          }
        }
      }
    '';
  };
}
