{ images, prometheus-jmx-httpserver }:

images.buildImageForPackage {
  name = "prometheus-jmx-httpserver";

  package = prometheus-jmx-httpserver;
  fromImage = images.jre;

  config = {
    Env = [
      "PATH=/bin"
    ];
    ExposedPorts = {
      "9404/tcp" = {};
    };
  };
}
