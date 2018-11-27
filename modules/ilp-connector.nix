{ config, lib, k8s, ... }:

with k8s;
with lib;

let
  environments = [
    "production"
    "test"
  ];
  plugins = [
    "ilp-plugin-btp"
    "ilp-plugin-mini-accounts"
    "ilp-plugin-xrp-paychan"
    "ilp-plugin-lightning"
    "ilp-plugin-xrp-asym-server"
  ];
  rateBackends = [
    "ecb"
    "ecb-plus-xrp"
    "ecb-plus-coinmarketcap"
    "one-to-one"
  ];
  stores = [
    "leveldown"
    "memdown"
  ];
  middleware = [
    "errorHandler"
    "deduplicate"
    "rateLimit"
    "maxPacketAmount"
    "throughput"
    "balance"
    "validateFulfillment"
    "expire"
    "stats"
  ];
  moduleToAttrs = value:
    if isAttrs value
    then mapAttrs (n: v: moduleToAttrs v) (filterAttrs (n: v: !(hasPrefix "_" n) && v != null) value)
    else if isList value
    then map (v: moduleToAttrs v) value
    else value;
in {
  config.kubernetes.moduleDefinitions.ilp-connector.module = {name, config, module, ...}: {
    options = {
      image = {
        connector = mkOption {
          description = "Docker image to use";
          type = types.str;
          default = "uroshercog/ilp-connector";
        };
        spsp = mkOption {
          description = "Docker image to use";
          type = types.str;
          default = "uroshercog/ilp-spsp";
        };
      };

      environment = mkOption {
        description = "The mode in which to run the connector";
        example = "production";
        type = types.enum environments;
        default = "production";
      };

      ilpAddress = mkOption {
        description = "The ILP address to use";
        example = "g.hub";
        type = types.str;
        default = "unknown";
      };

      ilpAddressInheritFrom = mkOption {
        description = "The parent from which to inherit the ILP address from";
        type = types.str;
        default = "";
      };

      accounts = mkOption {
        description = "Enabled accounts";
        default = {};
        type = types.attrsOf (types.submodule ({name, ...}: {
          options = {
            relation = mkOption {
              description = "Relationship between the connector and the counterparty that the account is with";
              type = types.enum ["peer" "parent" "child"];
            };

            plugin = mkOption {
              description = "Name or instance of the ILP plugin that should be used for this account";
              type = types.enum plugins;
            };

            assetCode = mkOption {
              description = "Currency code or other asset identifier that will be passed to the backend to select the correct rate for this account";
              type = types.str;
            };

            assetScale = mkOption {
              description = "Currency code or other asset scale that will be passed to the backend to select the correct rate for this account";
              type = types.int;
            };

            balance = {
              maximum = mkOption {
                description = "Maximum balance (in this account's indivisible base units) the connector will allow";
                type = types.nullOr types.str;
                default = null;
              };
              minimum = mkOption {
                description = "Minimum balance (in this account's indivisible base units) the connector must maintain";
                type = types.nullOr types.str;
                default = null;
              };
              settleThreshold = mkOption {
                description = "Balance (in this account's indivisible base units) numerically below which the connector will automatically initiate a settlement";
                type = types.nullOr types.str;
                default = null;
              };
              settleTo = mkOption {
                description = "Balance (in this account's indivisible base units) the connector will attempt to reach when settling";
                type = types.nullOr types.str;
                default = null;
              };
            };

            ilpAddressSegment = mkOption {
              description = "What segment will be appended to the connector's ILP address to form this account's ILP address";
              type = types.nullOr types.str;
              default = null;
            };

            maxPacketAmount = mkOption {
              description = "Maximum amount per packet for incoming prepare packets. Connector will reject any incoming prepare packets from this account with a higher amount";
              type = types.nullOr types.str;
              default = null;
            };

            # TODO(uh): What is here?
            options = mkOption {
              description = "Plugin specific options";
              type = types.nullOr types.attrs;
              default = null;
            };

            rateLimit = mkOption {
              description = "Maximum rate of incoming packets. Limit is implemented as a token bucket with a constant refill rate";
              type = types.nullOr (types.attrsOf (types.submodule ({name, ...}: {
                  options = {
                    capacity = mkOption {
                      description = "Maximum number of tokens in the bucket";
                      type = types.nullOr types.int;
                    };
                    refillCount = mkOption {
                      description = "How many tokens are refilled per period, per second";
                      type = types.nullOr types.int;
                    };
                    refillPeriod = mkOption {
                      description = "Length of time during which the token balance increases by refillCount tokens, in milliseconds";
                      type = types.nullOr types.int;
                    };
                  };
                })));
              default = null;
            };

            sendRoutes = mkOption {
              description = "Whether we should receive and process route broadcasts from this peer";
              type = types.bool;
              default = true;
            };

            throughput = mkOption {
              description = "Configuration to limit the total amount sent via Interledger per unit of time";
              type = types.nullOr (types.attrsOf (types.submodule ({name, ...}: {
                options = {
                  incomingAmount = mkOption {
                    description = "Maximum incoming throughput amount for incoming packets, per second";
                    type = types.nullOr types.str;
                  };
                  outgoingAmount = mkOption {
                    description = "Maximum throughput amount for outgoing packets, per second";
                    type = types.nullOr types.str;
                  };
                  refillPeriod = mkOption {
                    description = "Length of time during which the token balance increases by incomingAmount/outgoingAmount tokens, in milliseconds";
                    type = types.nullOr types.int;
                  };
                };
              })));
              default = null;
            };
          };
        }));
      };

      accountsSecrets = mkOption {
        description = "A list of account secrets, that should be added as env variables";
        type = types.attrsOf (types.submodule ({name, ...}: {
            options = {
              secret = mkSecretOption {
                default.key = "secret";
              };
            };
          }));
        default = {};
      };

      defaultRoute = mkOption {
        description = "Which account should be used as the default route for all other traffic";
        type = types.str;
        default = "auto";
      };

      routes = mkOption {
        type = types.listOf (types.attrsOf (types.submodule ({name, ...}: {
          options = {
            targetPrefix = mkOption {
              description = "ILP address prefix that this route applies to";
              type = types.nullOr types.str;
            };
            peerId = mkOption {
              description = "ID of the account that destinations matching targetPrefix should be forwarded to";
              type = types.nullOr types.str;
            };
          };
        })));
        default = [];
      };

      spread = mkOption {
        type = types.float;
        default = 0.0;
      };

      minMessageWindow = mkOption {
        description = "Minimum time the connector wants to budget for getting a message to the accounts its trading on. In milliseconds";
        type = types.int;
        default = 1000;
      };

      maxHoldTime = mkOption {
        description = "Maximum duration (in milliseconds) the connector is willing to place funds on hold while waiting for the outcome of a transaction";
        type = types.int;
        default = 30000;
      };

      routing = {
        broadcast = {
          enabled = mkOption {
            description = "Whether to broadcast known routes";
            type = types.bool;
            default = false;
          };

          interval = mkOption {
            description = "Frequency at which the connector broadcasts its routes to adjacent connectors, in milliseconds";
            type = types.int;
            default = 30000;
          };
        };
        cleanup = mkOption {
          description = "The frequency at which the connector checks for expired routes, in milliseconds";
          type = types.int;
          default = 1000;
        };
        expiry = mkOption {
          description = "The maximum age of a route provided by this connector, in milliseconds";
          type = types.int;
          default = 45000;
        };
        secret = mkSecretOption {
          description = "Seed used for generating routing table auth values";
          default.key = "secret";
        };
      };

      ratesBackend = {
        type = mkOption {
          description = "Name of the rate provider backend";
          type = types.enum rateBackends;
          default = "ecb";
        };
        config = mkOption {
          description = "Additional configuration for the backend";
          type = types.nullOr types.attrs;
          default = null;
        };
      };

      store = {
        type = mkOption {
          description = "Name of the store";
          type = types.enum stores;
          default = "leveldown";
        };
        config = mkOption {
          description = "Additional configuration for the store";
          type = types.nullOr types.attrs;
          default = null;
        };
      };

      middleware = {
        enable = mkOption {
          type = types.attrsOf (types.submodule ({name, ...}: {
              options = {
                type = mkOption {
                  description = "Middleware to enable";
                  type = types.enum middleware;
                };
                options = mkOption {
                  description = "Middle options";
                  type = types.nullOr types.attrs;
                  default = null;
                };
              };
            }));
          default = {};
        };
        disable = mkOption {
          description = "Name of the middleware to be removed";
          type = types.listOf (types.enum middleware);
          default = [];
        };
      };

      reflectPayments = mkOption {
        description = "Whether to allow routing payments back to the account that sent them";
        type = types.bool;
        default = true;
      };

      initialConnectTimeout = mkOption {
        description = "How long the connector should wait for account plugins to connect before launching other subsystems, in milliseconds";
        type = types.int;
        default = 10000;
      };

      adminApi = {
        enable = mkOption {
          description = "Whether to enable the administation API";
          type = types.bool;
          default = false;
        };
        port = mkOption {
          description = "Which port the admin API should listen on";
          type = types.int;
          default = 7780;
        };
        host = mkOption {
          description = "Host to bind the administation API to";
          type = types.str;
          default = "127.0.0.1";
        };
      };

      collectDefaultMetrics = mkOption {
        description = "Whether the Prometheus exporter should include system metrics or not";
        type = types.bool;
        default = false;
      };

      extraConnectorPorts = mkOption {
        description = "Extra ports to expose";
        type = types.listOf types.int;
        default = [];
      };

      spsp = {
        enable = mkOption {
          description = "Whether to enable the SPSP server";
          type = types.bool;
          default = true;
        };
        name = mkOption {
          description = "Name with which to authenticaticate with connector when establishing the BTP connecton";
          type = types.str;
          default = "connector";
        };
        secret = mkSecretOption {
          description = "Secret used to authenticaticate with the connector when establishing the BTP connecton";
          default.key = "secret";
        };
      };
    };

    config = {
      kubernetes.resources.statefulSets.ilp-connector = {
        metadata = {
          name = name;
          labels.app = name;
        };
        spec = {
          replicas = 1;
          serviceName = module.name;
          selector.matchLabels.app = name;
          updateStrategy.type = "RollingUpdate";
          template = {
            metadata = {
              labels.app = name;
            };
            spec = {
              containers = {
                connector = {
                  image = config.image.connector;

                  env = {
                    CONNECTOR_PLUGINS.value = ""; # concatStringsSep "," (unique (mapAttrsToList (n: v: v.plugin) config.accounts));
                    CONNECTOR_ENV.value = config.environment;
                    CONNECTOR_ILP_ADDRESS.value = config.ilpAddress;
                    CONNECTOR_ILP_ADDRESS_INHERIT_FROM = mkIf (config.ilpAddressInheritFrom != "") {
                      value = config.ilpAddressInheritFrom;
                    };
                    CONNECTOR_ACCOUNTS.value = builtins.toJSON (moduleToAttrs config.accounts);
                    CONNECTOR_DEFAULT_ROUTE.value = config.defaultRoute;
                    CONNECTOR_ROUTES.value = builtins.toJSON config.routes;
                    CONNECTOR_SPREAD.value = toString config.spread;
                    CONNECTOR_MIN_MESSAGE_WINDOW.value = toString config.minMessageWindow;
                    CONNECTOR_MAX_HOLD_TIME.value = toString config.maxHoldTime;
                    CONNECTOR_ROUTE_BROADCAST_ENABLED.value = boolToString config.routing.broadcast.enabled;
                    CONNECTOR_ROUTE_BROADCAST_INTERVAL = mkIf (config.routing.broadcast.enabled) {
                      value = config.routing.broadcast.interval;
                    };
                    CONNECTOR_ROUTE_CLEANUP_INTERVAL.value = toString config.routing.cleanup;
                    CONNECTOR_ROUTE_EXPIRY.value = toString config.routing.expiry;
                    CONNECTOR_ROUTING_SECRET = k8s.secretToEnv config.routing.secret;
                    CONNECTOR_BACKEND.value = config.ratesBackend.type;
                    CONNECTOR_BACKEND_CONFIG = mkIf (config.ratesBackend.config != null) {
                      value = builtins.toJSON config.ratesBackend.config;
                    };
                    CONNECTOR_STORE.value = config.store.type;
                    CONNECTOR_STORE_PATH.value = "/storage";
                    CONNECTOR_STORE_CONFIG = mkIf (config.store.config != null) {
                      value = builtins.toJSON config.store.config;
                    };
                    CONNECTOR_MIDDLEWARES.value = builtins.toJSON config.middleware.enable;
                    CONNECTOR_DISABLE_MIDDLEWARE.value = builtins.toJSON config.middleware.disable;
                    CONNECTOR_REFLECT_PAYMENTS.value = boolToString config.reflectPayments;
                    CONNECTOR_INITIAL_CONNECT_TIMEOUT.value = toString config.initialConnectTimeout;
                    CONNECTOR_ADMIN_API.value = boolToString config.adminApi.enable;
                    CONNECTOR_ADMIN_API_PORT = mkIf (config.adminApi.enable) {
                      value = config.adminApi.port;
                    };
                    CONNECTOR_ADMIN_API_HOST = mkIf (config.adminApi.enable) {
                      value = config.adminApi.host;
                    };
                    CONNECTOR_COLLECT_DEFAULT_METRICS.value = boolToString config.collectDefaultMetrics;
                  } // (mapAttrs (name: value: k8s.secretToEnv value.secret) config.accountsSecrets);

                  volumeMounts = [{
                    name = "store";
                    mountPath = "/storage";
                  }];

                  ports = (map (port: {containerPort = port;}) config.extraConnectorPorts)
                     ++ (optionals config.adminApi.enable [{ containerPort = config.adminApi.port; }]);
                };
                spsp = mkIf (config.spsp.enable) {
                  image = config.image.spsp;

                  ports = [{
                    containerPort = 80;
                  }];

                  env = {
                    # TODO: use secret
                    # TODO: connect to the local connector
                    ILP_CREDENTIALS.value = "{\"server\": \"btp+ws://${config.spsp.name}:secret@ilp-connector:7768\"}";
                  };
                };
              };
            };
          };
          volumeClaimTemplates = [{
            metadata.name = "store";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = "1G";
            };
          }];
        };
      };

      kubernetes.resources.services = {
        ilp-connector = {
          metadata.name = name;
          metadata.labels.app = name;

          spec = {
            selector.app = name;

            ports = [{
              name = "port";
              port = 7768;
              targetPort = 7768;
            }]
            ++ (map (port: {
              name = "${toString port}";
              port = port;
              targetPort = port;
            }) config.extraConnectorPorts)
            ++ (optionals config.adminApi.enable [{
              name = "admin";
              port = config.adminApi.port;
              targetPort = config.adminApi.port;
            }])
            ++ (optionals config.spsp.enable [{
              name = "spsp";
              port = 80;
              targetPort = 80;
            }]);
          };
        };
      };
    };
  };
}
