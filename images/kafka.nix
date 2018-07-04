{ images, apacheKafka }:

images.buildImageForPackage {
  name = "kafka";

  package = apacheKafka;

  config = {
    Env = [
      "PATH=/bin"
    ];
    ExposedPorts = {
      "9092/tcp" = {};
    };
  };
}
