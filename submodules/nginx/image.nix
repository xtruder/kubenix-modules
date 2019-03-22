{ config, pkgs, kubenix, ... }:

{
  imports = [ kubenix.docker ];

  docker.images.nginx.image = pkgs.dockerTools.buildLayeredImage {
    name = "nginx";
    contents = [ pkgs.nginx ];
    extraCommands = ''
      mkdir etc
      chmod u+w etc
      echo "nginx:x:1000:1000::/:" > etc/passwd
      echo "nginx:x:1000:nginx" > etc/group
    '';
    config = {
      Cmd = ["nginx" "-c" "/etc/nginx.conf"];
      ExposedPorts = {
        "80/tcp" = {};
        "443/tcp" = {};
      };
    };
  };
}
