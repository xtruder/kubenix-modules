{ config, k8s, ... }:

{
  require = [./test.nix ../modules/logstash.nix];

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
