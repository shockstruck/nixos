# SPlayer-Next — Electron desktop music player (SPlayer-Dev/SPlayer-Next).
#
# Not in nixpkgs; upstream ships a prebuilt AppImage. We wrap it with
# `appimageTools.wrapType2`, which provides the FHS runtime Electron needs and
# exposes the app as `$out/bin/${pname}`.
#
# Pin/update path (maintenance burden — SHOA-1003):
#   1. Find the newest release tag:
#        curl -s https://api.github.com/repos/SPlayer-Dev/SPlayer-Next/releases/latest | jq -r .tag_name
#   2. Bump `version` below to that tag without the leading `v`.
#   3. Refresh the hash (SRI form). Either:
#        nix store prefetch-file --json \
#          "https://github.com/SPlayer-Dev/SPlayer-Next/releases/download/v<version>/splayer-next-<version>-x86_64.AppImage"
#      or set `hash = lib.fakeHash;`, build once, and copy the expected hash Nix reports.
#   4. If a release changes the internal `.desktop`/icon filenames or the Exec
#      line, update `extraInstallCommands` (the `--replace-fail` will fail loudly
#      if the Exec string drifts, which is intentional).
{
  appimageTools,
  fetchurl,
  lib,
  makeWrapper,
}:
let
  pname = "splayer-next";
  version = "1.0.0";

  src = fetchurl {
    url = "https://github.com/SPlayer-Dev/SPlayer-Next/releases/download/v${version}/splayer-next-${version}-x86_64.AppImage";
    hash = "sha256-11aQDxg76QtHG8cuRFGZRb5is1Ne5YercPXaI8la9Ug=";
  };

  appimageContents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  nativeBuildInputs = [ makeWrapper ];

  extraInstallCommands = ''
    install -Dm 644 ${appimageContents}/top.imsyy.splayer_next.desktop \
      $out/share/applications/top.imsyy.splayer_next.desktop
    install -Dm 644 ${appimageContents}/usr/share/icons/hicolor/512x512/apps/SPlayer-Next.png \
      $out/share/icons/hicolor/512x512/apps/SPlayer-Next.png
    substituteInPlace $out/share/applications/top.imsyy.splayer_next.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=splayer-next %U'
    wrapProgram "$out/bin/splayer-next" --add-flags "--no-sandbox"
  '';

  meta = {
    description = "Cross-platform desktop music player with rich lyric support and wide audio format compatibility";
    homepage = "https://github.com/SPlayer-Dev/SPlayer-Next";
    changelog = "https://github.com/SPlayer-Dev/SPlayer-Next/releases/tag/v${version}";
    license = lib.licenses.agpl3Only;
    mainProgram = "splayer-next";
    platforms = [ "x86_64-linux" ];
  };
}
