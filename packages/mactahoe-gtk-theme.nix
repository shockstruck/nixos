{ lib, stdenvNoCC, fetchFromGitHub, sassc, glib, libxml2, gtk3, getent, which }:

stdenvNoCC.mkDerivation {
  pname = "mactahoe-gtk-theme";
  version = "2026-08-08";

  src = fetchFromGitHub {
    owner = "vinceliuice";
    repo = "MacTahoe-gtk-theme";
    rev = "2026-08-08";
    hash = "sha256-UEJZFXCVox3KCTZqSeOILumKCbUIeDTzcbLjimtotEI=";
  };

  nativeBuildInputs = [ sassc glib libxml2 gtk3 getent which ];

  dontBuild = true;
  dontFixup = true;

  postPatch = ''
    substituteInPlace libs/lib-core.sh \
      --replace-fail 'MY_HOME=$(getent passwd "''${MY_USERNAME}" | cut -d: -f6)' 'MY_HOME="$HOME"' \
      --replace-fail 'SUDO_BIN="$(which sudo)"' 'SUDO_BIN=""' \
      --replace-fail 'if [[ ! -w "/root" ]]; then' 'if false; then'
    patchShebangs install.sh libs/lib-install.sh libs/lib-core.sh
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/themes
    HOME=$TMPDIR ./install.sh --dest $out/share/themes --silent-mode -c dark -o normal
    runHook postInstall
  '';

  meta = with lib; {
    description = "MacOS Tahoe-like GTK theme (dark variant)";
    homepage = "https://github.com/vinceliuice/MacTahoe-gtk-theme";
    license = licenses.gpl3Only;
    platforms = platforms.unix;
  };
}
