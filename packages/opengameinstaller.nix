# OpenGameInstaller — Electron front-end for the OpenGameInstaller addon-server
# (Nat3z/OpenGameInstaller). The addon-server runs in-process; there is no
# separate service to wire up.
#
# Not in nixpkgs; upstream ships a prebuilt AppImage. We unpack it with
# `appimageTools.extract` and run its `resources/app.asar` on nixpkgs'
# Electron of the same major — deliberately NOT `appimageTools.wrapType2`.
# wrapType2 runs the app inside a bubblewrap FHS sandbox, and that sandbox
# is fatal for OGI's Steam integration: a managed Steam shortcut starts OGI
# from Steam with `--game-id=N -- %command%` and OGI spawns Steam's own
# launch chain (steam-launch-wrapper → reaper → SteamLinuxRuntime →
# Proton) as its child (handlers/handler.library.ts
# executeWrapperCommandForAppSteam). From inside the appimage sandbox that
# chain exits 255 with no diagnostics on OGI's stderr, so every OGI-managed
# game sits on OGI's "Running wrapped launch" spinner. Run
# unsandboxed, OGI lives in Steam's environment exactly as upstream's
# AppImage does on a Steam Deck, and the chain runs where Steam expects it.
# The same applies to OGI's own Play button, which runs pressure-vessel via
# the umu zipapp it downloads.
#
# What the AppImage carries, and why nixpkgs' Electron can run it:
#   - Electron 40.10.2 (upstream bun.lock at the pinned tag) — electron_40
#     below is the same major, so the Node ABI matches.
#   - `resources/app.asar` only; no `app.asar.unpacked`. The native modules
#     (utp-native, node-datachannel, bufferutil, utf-8-validate, …) are
#     N-API prebuilds inside the asar, which Electron unpacks to a temp file
#     at load time itself.
#   - `app.isPackaged` is decided by the executable's basename, and nixpkgs'
#     binary is `electron`, so OGI would take its dev path (renderer from
#     http://localhost:8080, data dir under the store). Electron's own
#     escape hatch is the ELECTRON_FORCE_IS_PACKAGED env var
#     (shell/browser/api/electron_api_app.cc App::IsPackaged), set below.
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
#   4. Check the Electron major in upstream's bun.lock at the new tag
#      (`"electron@<major>.x.y"` under application/) and move the
#      `electron_<major>` argument below with it; a mismatch breaks the
#      native modules at runtime, not at build time.
#   5. If a release changes the internal `.desktop`/icon filenames or the Exec
#      line, update `installPhase` (the `--replace-fail` will fail loudly
#      if the Exec string drifts, which is intentional).
{ appimageTools
, electron_40
, fetchurl
, lib
, makeWrapper
, stdenvNoCC
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
stdenvNoCC.mkDerivation {
  inherit pname version;

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -Dm 644 ${appimageContents}/resources/app.asar \
      $out/share/opengameinstaller/app.asar

    install -Dm 644 ${appimageContents}/opengameinstaller-gui.desktop \
      $out/share/applications/opengameinstaller-gui.desktop
    install -Dm 644 ${appimageContents}/usr/share/icons/hicolor/0x0/apps/opengameinstaller-gui.png \
      $out/share/icons/hicolor/256x256/apps/opengameinstaller-gui.png
    substituteInPlace $out/share/applications/opengameinstaller-gui.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=opengameinstaller %U' \
      --replace-fail 'Categories=Development;' 'Categories=Game;'

    # Flags come before "$@", so a Steam shortcut's
    # `--game-id=N --no-sandbox -- %command%` lands after the asar path and
    # reaches OGI's argv parser intact (lib/single-instance-launch.ts).
    # --no-sandbox matches upstream's own desktop Exec line.
    #
    # OGI's Steam-shortcut and desktop-shortcut writers take the launcher
    # path from $APPIMAGE (helpers.app/platform.ts getOgiExecutablePath),
    # falling back to process.execPath — here nixpkgs' bare electron binary,
    # which would start Electron's default app instead of OGI.
    # /run/current-system/sw/bin rather than $out/bin so shortcuts survive
    # version bumps (this package is in environment.systemPackages via
    # modules/nixos/console/launchers.nix), and Steam's own FHS env
    # bind-mounts /run so the path resolves from inside the shortcut.
    # APPIMAGE has no other consumer in OGI (the self-updater uses relative
    # ../OpenGameInstaller-Setup.AppImage paths).
    makeWrapper ${electron_40}/bin/electron $out/bin/opengameinstaller \
      --add-flags "$out/share/opengameinstaller/app.asar" \
      --add-flags "--no-sandbox" \
      --set ELECTRON_FORCE_IS_PACKAGED 1 \
      --set APPIMAGE /run/current-system/sw/bin/opengameinstaller

    runHook postInstall
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
