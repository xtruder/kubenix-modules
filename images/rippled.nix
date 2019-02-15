{ images, rippled }:

images.buildImageForPackage {
  name = "rippled";

  package = rippled;

  config = {
    Entrypoint = "/bin/rippled";
    User = "app";
    Env = [
      "PATH=/bin"
    ];
    ExposedPorts = {
      "5005/tcp" = {};
      "5006/tcp" = {};
      "32235/tcp" = {};
    };
  };
}
