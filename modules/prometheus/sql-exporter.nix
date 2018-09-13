{ config, lib, k8s, pkgs, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.prometheus-sql-exporter.module = {config, module, ...}: let
    configuration = {
      global = {
        scrape_timeout = config.global.scrapeTimeout;
        scrape_timeout_offset = config.global.scrapeTimeoutOffset;
        min_interval = config.global.minInterval;
        max_connections = config.global.maxConnections;
        max_idle_connections = config.global.maxIdleConnections;
      };

      target = {
        data_source_name = config.target.dataSourceName;
        collectors = config.target.collectors;
      };

      collectors = mapAttrsToList (_: collector: {
        collector_name = collector.name;
        min_interval = collector.minInterval;

        metrics = mapAttrsToList (_: metric: {
          metric_name = metric.name;
          type = metric.type;
          help = metric.help;
          key_labels = metric.keyLabels;
          value_label = metric.valueLabel;
          values = metric.values;
          query = metric.query;
        }) collector.metrics;
      }) config.collectors;
    };
  in {
    options = {
      image = mkOption {
        description = "Prometheus sql exporter image";
        type = types.str;
        default = "githubfree/sql_exporter";
      };

      replicas = mkOption {
        description = "Number of prometheus sql exporter replicas to run";
        type = types.int;
        default = 1;
      };

      global = {
        scrapeTimeout = mkOption {
          description = ''
			Scrape timeouts ensure that:
			  (i)  scraping completes in reasonable time and
			  (ii) slow queries are canceled early when the database is already under heavy load
			Prometheus informs targets of its own scrape timeout (via the "X-Prometheus-Scrape-Timeout-Seconds" request header)
			so the actual timeout is computed as:
			  min(scrape_timeout, X-Prometheus-Scrape-Timeout-Seconds - scrape_timeout_offset)
			
			If scrape_timeout <= 0, no timeout is set unless Prometheus provides one. The default is 10s.
          '';
          type = types.str;
          default = "10s";
          example = "10s";
        };

        scrapeTimeoutOffset = mkOption {
          description = ''Offset subtracted from Prometheus' scrape_timeout to
            give us some headroom and prevent Prometheus from timing out first.'';
          type = types.str;
          default = "500ms";
          example = "500ms";
        };

        minInterval = mkOption {
          description = ''
            Minimum interval between collector runs: by default (0s) collectors
            are executed on every scrape.
          '';
          type = types.str;
          default = "0s";
        };

        maxConnections = mkOption {
          description = ''
            Maximum number of open connections to any one target. Metric queries
            will run concurrently on multiple connections, 

            If max_connections <= 0, then there is no limit on the number of open connections.
          '';
          type = types.int;
          default = 3;
        };

        maxIdleConnections = mkOption {
          description = ''
            Maximum number of idle connections to any one target. Unless you use
            very long collection intervals, this should always be the same as max_connections.
          '';
          type = types.int;
          default = config.global.maxConnections;
        };
      };

      target = {
        dataSourceName = mkOption {
          description = ''
            Data source name in a format:

            * MySQL: mysql://user:passw@protocol(host:port)/dbname
            * PostgreSQL: postgres://user:passw@host:port/dbname
            * MSSQL Server: sqlserver://user:passw@host:port/instance
            * Clickhouse: clickhouse://host:port?username=user&password=passw&database=dbname
          '';
          type = types.str;
          example = "sqlserver://prom_user:prom_password@dbserver1.example.com:1433";
        };

        collectors = mkOption {
          description = "List of collectors to run on target";
          type = types.listOf types.str;
          default = mapAttrsToList (_: collector: collector.name) config.collectors;
          example = ["mssql_standard"];
        };
      };

      collectors = mkOption {
        description = ''
          A collector is a named set of related metrics that are collected together.
          It can be referenced by name, possibly along with other collectors.
        '';
        type = types.attrsOf (types.submodule ({name, config, ...}: {
          options = {
            name = mkOption {
              description = "Collector name";
              type = types.str;
              default = name;
            };

            minInterval = mkOption {
              description = ''
                Minimum interval between collector runs: by default (0s) collectors
                are executed on every scrape.
              '';
              type = types.str;
              default = "0s";
            };

            metrics = mkOption {
              description = ''
                A metric is a Prometheus metric with name, type, help text and
                (optional) additional labels, paired with exactly one query to
                populate the metric labels and values from.

                The result columns conceptually fall into two categories:
                * zero or more key columns: their values will be directly mapped
                  to labels of the same name;
                * one or more value columns:
                  * if exactly one value column, the column name name is ignored
                    and its value becomes the metric value
                  * with multiple value columns, a `value_label` must be defined;
                    the column name will populate this label and
                    the column value will populate the metric value.
              '';
              type = types.attrsOf (types.submodule ({name, config, ...}: {
                options = {
                  name = mkOption {
                    description = "Metric name";
                    type = types.str;
                    default = name;
                  };

                  help = mkOption {
                    description = "Metric help text";
                    type = types.str;
                    default = "";
                  };

                  type = mkOption {
                    description = "Metric type (either gauge or counter)";
                    type = types.enum ["gauge" "counter"];
                  };

                  keyLabels = mkOption {
                    description = "Optional set of labels derived from key columns";
                    type = types.listOf types.str;
                    default = [];
                  };

                  values = mkOption {
                    description = "List of column values to record in a metric";
                    type = types.listOf types.str;
                  };

                  valueLabel = mkOption {
                    description = ''
                      Label populated with the value column name, configured via `values`.
                      Required when multiple value columns are configured.
                    '';
                    type = types.str;
                    default = "operation";
                  };

                  query = mkOption {
                    description = "Query to run";
                    type = types.lines;
                    example = ''
                      SELECT Market, max(UpdateTime) AS LastUpdateTime
                      FROM MarketPrices
                      GROUP BY Market
                    '';
                  };
                };
              }));
            };
          };
        })); 
      };

      extraArgs = mkOption {
        description = "Prometheus server additional options";
        default = [];
        type = types.listOf types.str;
      };
    };

    config = {
      kubernetes.resources.deployments.prometheus-sql-exporter = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          selector.matchLabels.app = module.name;
          template = {
            metadata.labels.app = module.name;
            metadata.annotations."kubenix/config-hash" =
              builtins.hashString "md5" (builtins.toJSON configuration);
            spec = {
              containers.blackbox-exporter = {
                image = config.image;
                imagePullPolicy = "IfNotPresent";
                args = ["--config.file=/config/sql_exporter.yaml"] ++ config.extraArgs;
                resources = {
                  limits.memory = "300Mi";
                  requests.memory = "50Mi";
                };
                ports = [{
                  name = "http";
                  containerPort = 9399;
                }];
                livenessProbe.httpGet = {
                  path = "/metrics";
                  port = "http";
                };
                volumeMounts = [{
                  mountPath = "/config";
                  name = "config";
                }];
              };

              volumes.config.configMap.name = module.name;
            };
          };
        };
      };

      kubernetes.resources.configMaps.prometheus-blackbox-exporter = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        data."sql_exporter.yaml" = toYAML configuration;
      };

      kubernetes.resources.services.prometheus-blackbox-exporter = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          ports = [{
            name = "http";
            port = 9399;
            protocol = "TCP";
          }];
          selector.app = module.name;
        };
      };
    };
  };
}
