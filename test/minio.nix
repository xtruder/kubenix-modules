{ config, k8s, ... }:

with k8s;

{
  require = import ../services/module-list.nix;

  kubernetes.modules.minio = {
    module = "minio";
    configuration = {
      replicas = 1;
      accessKey.name = "minio";
      secretKey.name = "minio";
    };
  };

  kubernetes.modules.deployer = {
    module = "deployer";
    configuration = {
      vars.s3_access_key.valueFrom.secretKeyRef = {
        name = "minio";
        key = "accesskey";
      };
      vars.s3_secret_key.valueFrom.secretKeyRef = {
        name = "minio";
        key = "secretkey";
      };
      configuration = {
        variable.s3_access_key.type = "string";
        variable.s3_secret_key.type = "string";
        provider.s3 = {
          s3_server = "minio:9000";
          s3_region = "us-east-1";
          s3_access_key = ''''${var.s3_access_key}'';
          s3_secret_key = ''''${var.s3_secret_key}'';
          s3_api_signature = "v4";
          s3_ssl = false;
          s3_debug = true;
        };
        resource.s3_bucket.mybucket.bucket = "mybucket";
      };
    };
  };

  kubernetes.resources.secrets.minio.data = {
    accesskey = toBase64 "AKIAIOSFODNN7EXAMPLE";
    secretkey = toBase64 "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";
  };
}
