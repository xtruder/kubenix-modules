{ images, confluent }:

images.buildImageForPackage {
  name = "ksql";

  package = confluent;

  config = {
    Env = [
      "PATH=/bin"
    ];
    ExposedPorts = {
      "8088/tcp" = {};
    };
  };
}
