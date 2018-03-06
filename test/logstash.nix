{ config, k8s, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.logstash = {
    module = "logstash";
    configuration.configuration = ''
      input {
				generator { }
			}

      output {
        stdout {
          codec => rubydebug
        }
      }
    '';
  };
}
