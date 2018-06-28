{ images, zookeeper }:

images.buildImageForPackage {
  name = "zookeeper";

  package = zookeeper;

  config = {
    Env = [
      "PATH=/bin"
    ];
    ExposedPorts = {
      "2181/tcp" = {};
      "2888/tcp" = {};
      "3888/tcp" = {};
    };
  };
}
