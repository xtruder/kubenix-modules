{ stdenv, buildGo110Package, fetchFromGitHub }:

buildGo110Package rec {
  name = "metacontroller-${version}";
  version = "v0.3.1";

  goPackagePath = "metacontroller.app";
  subPackages = [ "." ];
  goDeps = ./deps.nix;

  src = fetchFromGitHub {
    owner = "GoogleCloudPlatform";
    repo = "metacontroller";
    rev = version;
    sha256 = "1r4lsgf5r6ai071lghdbvw3ira8s4qj9d153zhxbqg16ypd4clwz";
  };

  preBuild = ''
    rm -rf go/src/github.com/0xRLG/ocworkqueue/vendor
  '';

  meta = with stdenv.lib; {
    homepage = "https://metacontroller.app/";
    description = "Lightweight Kubernetes controllers as a service";
    platforms = platforms.linux;
    license = license.asl20;
    maintainers = with maintainers; [ offline ];
  };
}
