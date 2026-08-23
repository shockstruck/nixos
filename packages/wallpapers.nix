{ stdenv }:
stdenv.mkDerivation {
  pname = "pa-wallpapers";
  version = "1.0.0";
  src = ./wallpapers;
  installPhase = ''
    mkdir -p $out/share/wallpapers
    cp -r $src/. $out/share/wallpapers/
  '';
}
