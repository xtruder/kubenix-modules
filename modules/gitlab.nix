{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.gitlab.module = {name, config, ...}: let
    gitlabCEImage = "gitlab/gitlab-ce:10.6.2-ce.0";
    gitlabEEImage = "gitlab/gitlab-ee:10.6.2-ee.0";
  in {
    options = {
      image = mkOption {
        description = "Name of the gitlab image to use";
        type = types.str;
        default =
          if config.enterprise.enable
          then gitlabEEImage
          else gitlabCEImage;
      };

      replicas = mkOption {
        description = "Number of gitlab replicas to run";
        type = types.int;
        default = 1;
      };

      baseDomain = mkOption {
        description = "GitLab base domain";
        type = types.str;
      };

      externalScheme = mkOption {
        description = "Gitlab external scheme";
        type = types.enum ["http" "https"];
        default = "https";
      };

      externalHostname = mkOption {
        description = "GitLab externam hostname";
        type = types.str;
        default = "gitlab.${config.baseDomain}";
      };

      postgres = {
        host = mkOption {
          description = "Postgresql hostname";
          type = types.str;
          default = "postgres";
        };

        username = mkSecretOption {
          description = "Postgres user";
          default.key = "username";
        };

        password = mkSecretOption {
          description = "Postgres password";
          default.key = "password";
        };

        database = mkOption {
          description = "Name of the postgres database";
          default = "gitlab";
        };

        ssl = {
          enable = mkOption {
            description = "Whether to enable ssl on postgrsql";
            type = types.bool;
            default = false;
          };

          cert = mkSecretOption {
            description = "GitLab postgresql cert";
            default = null;
          };

          key = mkSecretOption {
            description = "GitLab postgresql key";
            default = null;
          };

          ca = mkSecretOption {
            description = "GitLab postgresql ca";
            default = null;
          };
        };
      };

      redis = {
        host = mkOption {
          description = "Gitlab redis host";
          type = types.str;
          default = "redis";
        };

        port = mkOption {
          description = "GitLab redis port";
          type = types.int;
          default = 6379;
        };

        password = mkSecretOption {
          description = "GitLab redis password";
          default = null;
        };
      };

      pages = {
        enable = mkOption {
          description = "Wheter to enable gitlab pages";
          type = types.bool;
          default = false;
        };

        externalScheme = mkOption {
          description = "Gitlab pages external scheme";
          type = types.enum ["http" "https"];
          default = "http";
        };

        externalHostname = mkOption {
          description = "Gitlab pages external hostname";
          type = types.str;
          default = "pages.${config.baseDomain}";
        };
      };

      registry = {
        enable = mkOption {
          description = "Wheter to enable gitlab docker registry";
          type = types.bool;
          default = false;
        };

        externalScheme = mkOption {
          description = "Gitlab docker registry external scheme";
          type = types.enum ["http" "https"];
          default = "http";
        };

        externalHostname = mkOption {
          description = "Gitlab docker registry external domain";
          type = types.str;
          default = "registry.${config.baseDomain}";
        };
      };

      mattermost = {
        enable = mkOption {
          description = "Whether to enable gitlab integrated mattermost service";
          type = types.bool;
          default = false;
        };

        appSecret = mkSecretOption {
          description = "GitLab integrated mattermost app secret";
          default = null;
        };

        appId = mkSecretOption {
          description = "GitLab integrated mattermost app id";
          default = null;
        };
        
        externalScheme = mkOption {
          description = "GitLab integrated mattermost external scheme";
          type = types.enum ["http" "https"];
          default = "http";
        };

        externalDomain = mkOption {
          description = "GitLab integrated mattermost external domain";
          type = types.str;
          default = "mattermost.${config.baseDomain}";
        };
      };

      runners = {
        initialRegistrationToken = mkSecretOption {
          description = "GitLab runner initial registration token";
          default = null;
        };
      };

      enterprise = {
        enable = mkOption {
          description = "Whether to enable gitlab enterprise edition";
          type = types.bool;
          default = false;
        };

        license = mkSecretOption {
          description = "GitLab enterprise edition license";
          default.key = "license";
        };
      };

      extraConfig = {
        description = "GitLab extra ruby config, see https://docs.gitlab.com/omnibus/settings/configuration.html";
        type = types.lines;
        example = ''
          gitlab_rails['smtp_enable'] = true
          gitlab_rails['smtp_address'] = "smtp.example.org"
        '';
      };
    };

    config = {
      kubernetes.resources.deployments.gitlab = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          replicas = config.replicas;
          selector.matchLabels.app = name;
          template = {
            metadata.labels.app = name;
            spec = {
              containers.gitlab = {
                image = config.image;
                imagePullPolicy = mkDefault "IfNotPresent";
                command = ["/bin/bash" "-c" ''
                  sed -i \"s/environment ({'GITLAB_ROOT_PASSWORD' => initial_root_password }) if initial_root_password/environment ({'GITLAB_ROOT_PASSWORD' => initial_root_password, 'GITLAB_SHARED_RUNNERS_REGISTRATION_TOKEN' => node['gitlab']['gitlab-rails']['initial_shared_runners_registration_token'] })/g\" /opt/gitlab/embedded/cookbooks/gitlab/recipes/database_migrations.rb && exec /assets/wrapper
                ''];
                env = {
                  GITLAB_EXTERNAL_SCHEME.value = config.externalScheme;
                  GITLAB_EXTERNAL_HOSTNAME.value = config.externalHostname;
                  GITLAB_REGISTRY_EXTERNAL_SCHEME.value = config.registry.externalScheme;
                  GITLAB_REGISTRY_EXTERNAL_HOSTNAME.value = config.registry.externalHostname;
                  GITLAB_MATTERMOST_EXTERNAL_SCHEME.value = config.mattermost.externalScheme;
                  GITLAB_MATTERMOST_EXTERNAL_HOSTNAME.value = config.mattermost.externalHostname;
                  POSTGRES_USER = k8s.secretToEnv config.postgres.username;
                  POSTGRES_PASSWORD = k8s.secretToEnv config.postgres.password;
                  POSTGRES_DB = k8s.secretToEnv config.postgres.database;
                };
                ports = [{
                  name = "http";
                  containerPort = 80;
                } {
                  name = "https";
                  containerPort = 443;
                }];

                resources.requests = {
                  cpu = "100m";
                  memory = "50Mi";
                };

                volumeMounts = mkIf (config.configuration != null) [{
                  name = "config";
                  mountPath = "/etc/nginx/nginx.conf";
                  subPath = "nginx.conf";
                }];
              };
              volumes = mkIf (config.configuration != null) {
                config.configMap.name = name;
              };
            };
          };
        };
      };

      kubernetes.resources.serviceAccounts.nginx = {
        metadata.name = name;
        metadata.labels.app = name;
      };

      kubernetes.resources.configMaps = mkIf (config.configuration != null) {
        nginx = {
          metadata.name = name;
          data."nginx.conf" = config.configuration;
        };
      };

      kubernetes.resources.services.nginx = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          ports = [{
            name = "http";
            port = 80;
          } {
            name = "https";
            port = 443;
          }];
          selector.app = name;
        };
      };
    };
  };
}
