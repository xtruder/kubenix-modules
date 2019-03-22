{ config, kubenix, lib, pkgs, ... }:

with lib;

{
  imports = [
    kubenix.modules.k8s
    kubenix.modules.docker
  ];

  test = {
    name = "mariadb-1-x";
    description = "Test for mariadb submodule";
    extraConfiguration = {
      environment.systemPackages = [ pkgs.mysql ];
      services.kubernetes.kubelet.seedDockerImages = config.docker.export;
      services.kubernetes.addons.local-path-provisioner.enable = true;
    };
    testScript = ''
      $kube->waitUntilSucceeds("kubectl apply -f ${toYAML config.kubernetes.generated}");
      $kube->waitUntilSucceeds("kubectl get deployment -o go-template mariadb --template={{.status.readyReplicas}} | grep 1");
      $kube->waitUntilSucceeds("mysql -h mariadb.default.svc.cluster.local -u user -pmypassword test -e 'select * from test'");
    '';
  };

  submodules.imports = [
    ./1.x.nix
  ];

  docker.registry.url = mkForce "";

  submodules.instances.mariadb = {
    submodule = "mariadb";

    args = {
      rootPassword.name = "mysql-root-password";
      extraArgs = ["log-bin-trust-function-creators"];
      mysql = {
        database = "test";
        user = {
          name = "mysql-user";
          key = "username";
        };
        password = {
          name = "mysql-user";
          key = "password";
        };
      };

      initdb."init.sql" = ''
        create table if not exists test (text varchar(255) not null);
        insert into test(text) values("abcd");
      '';
    };

    config = {
      kubernetes.api.secrets.mysql-user.data = {
        username = toBase64 "user";
        password = toBase64 "mypassword";
      };

      kubernetes.api.secrets.mysql-root-password.data = {
        password = toBase64 "mypassword";
      };
    };
  };
}
