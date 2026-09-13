# OpenGameInstaller — Electron front-end for the OpenGameInstaller addon-server
# (Nat3z/OpenGameInstaller). The addon-server runs in-process; there is no
# separate service to wire up.
#
# Not in nixpkgs; upstream ships a prebuilt AppImage. We wrap it with
# `appimageTools.wrapType2`, which provides the FHS runtime Electron needs and
# exposes the app as `$out/bin/${pname}`.
#
# The upstream self-updater cannot work from an immutable store path; do not
# try to disable it. Updates flow through a version bump in this file instead.
#
# Licence: AGPL-3.0-only per the upstream LICENSE files; application/package.json's
# "MIT" field is stale metadata.
#
# Pin/update path:
#   1. Find the newest release tag:
#        curl -s https://api.github.com/repos/Nat3z/OpenGameInstaller/releases/latest | jq -r .tag_name
#   2. Bump `version` below to that tag without the leading `v`.
#   3. Refresh the hash (SRI form). Either:
#        nix store prefetch-file --json \
#          "https://github.com/Nat3z/OpenGameInstaller/releases/download/v<version>/OpenGameInstaller-linux-pt.AppImage"
#      or set `hash = lib.fakeHash;`, build once, and copy the expected hash Nix reports.
#   4. If a release changes the internal `.desktop`/icon filenames or the Exec
#      line, update `extraInstallCommands` (the `--replace-fail` will fail loudly
#      if the Exec string drifts, which is intentional).
{ appimageTools
, fetchurl
, lib
, makeWrapper
}:
let
  pname = "opengameinstaller";
  version = "4.3.1";

  src = fetchurl {
    url = "https://github.com/Nat3z/OpenGameInstaller/releases/download/v${version}/OpenGameInstaller-linux-pt.AppImage";
    hash = "sha256-xGfiCGrMrSWBC/Ipe1socwefW/gj6hqEKpyie7tlPig=";
  };

  appimageContents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  nativeBuildInputs = [ makeWrapper ];

  extraInstallCommands = ''
    install -Dm 644 ${appimageContents}/opengameinstaller-gui.desktop \
      $out/share/applications/opengameinstaller-gui.desktop
    install -Dm 644 ${appimageContents}/usr/share/icons/hicolor/0x0/apps/opengameinstaller-gui.png \
      $out/share/icons/hicolor/256x256/apps/opengameinstaller-gui.png
    substituteInPlace $out/share/applications/opengameinstaller-gui.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=opengameinstaller %U' \
      --replace-fail 'Categories=Development;' 'Categories=Game;'
    wrapProgram "$out/bin/opengameinstaller" --add-flags "--no-sandbox"
  '';

  meta = {
    description = "Front-end GUI for OpenGameInstaller and the addon-server";
    homepage = "https://github.com/Nat3z/OpenGameInstaller";
    changelog = "https://github.com/Nat3z/OpenGameInstaller/releases/tag/v${version}";
    license = lib.licenses.agpl3Only;
    mainProgram = "opengameinstaller";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
