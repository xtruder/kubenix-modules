{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.mediawiki.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Elasticsearch image to use";
        type = types.str;
        default = "xtruder/mediawiki";
      };

      parsoidImage = mkOption {
        description = "Image to use for parsoid";
        type = types.str;
        default = "offlinehacker/parsoid";
      };

      url = mkOption {
        description = "Url for mediawiki service";
        type = types.str;
      };

      siteName = mkOption {
        description = "Mediawiki site name";
        type = types.str;
        default = "Company internal Wiki";
      };

      adminUser = mkOption {
        description = "Mediawiki admin user";
        type = types.str;
        default = "admin";
      };

      adminPassword = mkValueOrSecretOption {
        description = "Mediawiki admin password";
      };

      customConfig = mkOption {
        description = "Mediawiki custom config";
        type = types.lines;
        default = "";
      };

      storage = {
        size = mkOption {
          description = "Mediawiki storage size";
          default = "10G";
        };

        class = mkOption {
          description = "Mediawiki storage class";
          type = types.nullOr types.str;
          default = null;
        };
      };

      db = {
        type = mkOption {
          description = "Database type";
          type = types.enum ["mysql" "postgres"];
          default = "mysql";
        };

        name = mkOption {
          description = "Database name";
          type = types.str;
          default = "mediawiki";
        };

        host = mkOption {
          description = "Database host";
          type = types.str;
          default = "mysql";
        };

        port = mkOption {
          description = "Database port";
          type = types.int;
          default = 3306;
        };

        user = mkValueOrSecretOption {
          description = "Database user";
          default = "mediawiki";
        };

        pass = mkValueOrSecretOption {
          description = "Database password";
          default = "mediawiki";
        };
      };
    };

    config = {
      kubernetes.resources.deployments.mediawiki = {
        metadata = {
          name = name;
          labels.app = name;
        };
        spec = {
          replicas = 1;
          template = {
            metadata = {
              labels.app = name;
            };
            spec = {
              containers.parsoid = {
                image = config.parsoidImage;
                env = {
                  MW_URL.value = http://127.0.0.1;
                  PORT.value = "8000";
                };
              };

              containers.mediawiki = {
                image = config.image;

                volumeMounts = [{
                  name = "data";
                  mountPath = "/data";
                } {
                  name = "config";
                  mountPath = "/config";
                }];

                env = {
                  MEDIAWIKI_SITE_SERVER.value = config.url;
                  MEDIAWIKI_SITE_NAME.value = config.siteName;
                  MEDIAWIKI_ADMIN_USER.value = config.adminUser;
                  MEDIAWIKI_ADMIN_PASS = config.adminPassword;
                  MEDIAWIKI_DB_TYPE.value = config.db.type;
                  MEDIAWIKI_DB_HOST.value = config.db.host;
                  MEDIAWIKI_DB_PORT.value = toString config.db.port;
                  MEDIAWIKI_DB_USER = config.db.user;
                  MEDIAWIKI_DB_PASSWORD = config.db.pass;
                  MEDIAWIKI_DB_NAME.value = config.db.name;
                  MEDIAWIKI_UPDATE.value = "true";
                };

                lifecycle.postStart.exec.command =
                  ["/bin/cp" "/config/settings.php" "/data/CustomSettings.php"];

                ports = [{
                  containerPort = 80;
                }];

                readinessProbe.httpGet = {
                  path = "/index.php/Main_Page";
                  port = 80;
                };
              };

              volumes.config.configMap.name = name;
              volumes.data.persistentVolumeClaim.claimName = name;
            };
          };
        };
      };

      kubernetes.resources.services.mediawiki = {
        metadata.name = name;
        metadata.labels.app = name;

        spec.selector.app = name;

        spec.ports = [{
          name = "http";
          port = 80;
        } {
          name = "parsoid";
          port = 8000;
        }];
      };

      kubernetes.resources.persistentVolumeClaims.mediawiki.spec = {
        accessModes = ["ReadWriteOnce"];
        resources.requests.storage = config.storage.size;
        storageClassName = config.storage.class;
      };

      kubernetes.resources.configMaps.mediawiki.data."settings.php" =
        ''<?php
        ${config.customConfig}
        ?>'';
    };
  };
}
