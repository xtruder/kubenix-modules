{ lib, stdenv, dockerTools, buildEnv, bashInteractive, coreutils, nix, shadow, openssh, gnused, cacert, perl }:

with lib;

let
  passwd = ''
    root:x:0:0::/root:/bin/bash
    ${concatStringsSep "\n" (genList (i: "nixbld${toString (i+1)}:x:${toString (i+30001)}:30000::/var/empty:/run/current-system/sw/bin/nologin") 32)}
  '';

  group = ''
    root:x:0:
    nogroup:x:65534:
    nixbld:x:30000:${concatStringsSep "," (genList (i: "nixbld${toString (i+1)}") 32)}
  '';

  nsswitch = ''
    hosts: files dns myhostname mymachines
  '';
in dockerTools.buildImageWithNixDb {
  name = "nix-remote-builder";

  contents = [bashInteractive coreutils nix shadow openssh cacert gnused];

  config = {
    Cmd = ["/bin/sshd" "-D" "-e"];
    Env = [
      "PATH=/bin"
      "MANPATH=/share/man"
      "NIX_PAGER=cat"
      "GIT_SSL_CAINFO=${cacert}/etc/ssl/certs/ca-bundle.crt"
      "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
    ];
  };

  runAsRoot = ''
    #!${stdenv.shell}

    mkdir -m 1777 -p /tmp
    mkdir -p /etc/ssh
    mkdir -p /var/empty 
    mkdir -p /run
    mkdir -p /root

    echo '${passwd}' > /etc/passwd
    echo '${group}' > /etc/group
    echo '${nsswitch}' > /etc/nsswitch.conf

    echo "sshd:x:498:65534::/var/empty:/bin/nologin" >> /etc/passwd
    cp -R ${openssh}/etc/* /etc
    ${gnused}/bin/sed -i '/^PermitRootLogin/d' /etc/ssh/sshd_config
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
    ${openssh}/bin/ssh-keygen -f /etc/ssh/ssh_host_rsa_key -N "" -t rsa
    ${openssh}/bin/ssh-keygen -f /etc/ssh/ssh_host_dsa_key -N "" -t dsa
    ${openssh}/bin/ssh-keygen -f /etc/ssh/ssh_host_ecdsa_key -N "" -t ecdsa
    ${openssh}/bin/ssh-keygen -f /etc/ssh/ssh_host_ed25519_key -N "" -t ed25519
    echo "export SSL_CERT_FILE=$SSL_CERT_FILE" >> /etc/bashrc
    echo "export PATH=$PATH" >> /etc/bashrc
    echo "source /etc/bashrc" >> /etc/profile
  '';
}
