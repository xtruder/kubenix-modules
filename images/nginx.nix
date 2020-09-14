{ images, nginx }:

images.buildImageForPackage {
  name = "nginx";

  package = nginx;

  config = {
    Cmd = ["/bin/nginx"];
    User = "app";
    Env = [
      "PATH=/bin"
    ];
    ExposedPorts = {
      "80/tcp" = {};
      "443/tcp" = {};
    };
  };
}
