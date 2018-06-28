{ config, ... }:

{
  require = [
    ./test.nix
    ../modules/pritunl.nix
    ../modules/mongo.nix
  ];

  kubernetes.modules.mongo = {
    module = "mongo";
  };

  kubernetes.modules.pritunl = {
    module = "pritunl";

    configuration.kubernetes.resources.services.pritunl.spec.type = "LoadBalancer";
    configuration.mongodbUri = "mongodb://mongo-0.mongo:27017,mongo-1.mongo:2701,mongo-2.mongo:2701/pritunl?replicaSet=rs0";
  };
}
