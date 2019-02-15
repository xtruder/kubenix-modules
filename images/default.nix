{ pkgs
, lib
, dockerTools
, overrides ? (self: super: {})
}:

with lib;

let
  images = (self:
let
  buildImageForPackage = {
    package,

    name ? package.pname,

    tag ? null,

    contents ? [],

    extraCommands ? "",

    defaultContents ? [pkgs.cacert pkgs.busybox],

    config ? {}
  }: pkgs.dockerTools.buildLayeredImage {
    inherit name config;

    contents = [package] ++ contents ++ defaultContents;

    extraCommands = ''
      mkdir tmp
      chmod 1777 tmp

      chmod u+w etc

      echo "app:x:1000:1000::/:" > etc/passwd
      echo "app:x:1000:app" > etc/group

      ${extraCommands}
    '';
    maxLayers = 42;
  };

  callPackage = pkgs.newScope (pkgs // {
    images = self;
  });
in {
  inherit buildImageForPackage;

  zookeeper = callPackage ./zookeeper.nix {};

  kafka = callPackage ./kafka.nix {};

  ksql = callPackage ./ksql.nix {};
});

in fix' (extends overrides images)
