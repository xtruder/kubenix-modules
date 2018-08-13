{ pkgs
, kubenix
, images }:

let
  buildTest = test: extraOpts: kubenix.buildResources {
    configuration.imports = [test {
      _module.args.images = images;
    } extraOpts];
  };
in {
  bitcoind = buildTest ./bitcoind.nix {};
  dashd = buildTest ./dashd.nix {};
  rabbitmq = buildTest ./rabbitmq.nix {};
  elasticsearch = buildTest ./elasticsearch.nix {};
  elasticsearch-curator = buildTest ./elasticsearch-curator.nix {};
  redis = buildTest ./redis.nix {};
  nginx = buildTest ./nginx.nix {};
  galera = buildTest ./galera.nix {};
  etcd-operator = buildTest ./etcd-operator.nix {};
  deployer = buildTest ./deployer.nix {};
  rippled = buildTest ./rippled.nix {};
  zetcd = buildTest ./zetcd.nix {};
  kibana = buildTest ./kibana.nix {};
  parity = buildTest ./parity.nix {};
  mediawiki = buildTest ./mediawiki.nix {};
  beehive = buildTest ./beehive.nix {};
  minio = buildTest ./minio.nix {};
  prometheus = buildTest ./prometheus.nix {};
  prometheus-kubernetes = buildTest ./prometheus-kubernetes.nix {};
  grafana = buildTest ./grafana.nix {};
  kube-lego-gce = buildTest ./kube-lego-gce.nix {};
  pachyderm = buildTest ./pachyderm.nix {};
  etcd = buildTest ./etcd.nix {};
  vault = buildTest ./vault.nix {};
  vault-prod = buildTest ./vault-prod.nix {};
  vault-controller = buildTest ./vault-controller.nix {};
  vault-controller-k8s-auth = buildTest ./vault-controller-k8s-auth.nix {};
  vault-ui = buildTest ./vault-ui.nix {};
  #vault-login-k8s = buildTest ./vault-login-k8s.nix {};
  logstash = buildTest ./logstash.nix {};
  influxdb = buildTest ./influxdb.nix {};
  kubelog = buildTest ./kubelog.nix {};
  secret-restart-controller = buildTest ./secret-restart-controller.nix {};
  selfsigned-cert-deployer = buildTest ./selfsigned-cert-deployer.nix {};
  nginx-ingress = buildTest ./nginx-ingress.nix {};
  mongo = buildTest ./mongo.nix {};
  pritunl = buildTest ./pritunl.nix {};
  cloud-sql-proxy = buildTest ./cloud-sql-proxy.nix {};
  mariadb = buildTest ./mariadb.nix {};
  k8s-snapshot = buildTest ./k8s-snapshot.nix {};
  zookeeper = buildTest ./zookeeper.nix {};
  kafka = buildTest ./kafka.nix {};
  ksql = buildTest ./ksql.nix {};
  argo-ingress-controller = buildTest ./argo-ingress-controller.nix {};
  ambassador = buildTest ./ambassador.nix {};
}
