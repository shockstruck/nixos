# OpenGameInstaller — Electron front-end for the OpenGameInstaller addon-server,
# built from shockstruck/OpenGameInstaller (a fork of Nat3z/OpenGameInstaller).
# The addon-server runs in-process; there is no separate service to wire up.
#
# Not in nixpkgs; the fork ships a prebuilt AppImage (its `Build/release`
# workflow, same as upstream's). We unpack it with `appimageTools.extract`
# and run its `resources/app.asar` on nixpkgs' Electron of the same major —
# deliberately NOT `appimageTools.wrapType2`. wrapType2 runs the app inside a
# bubblewrap FHS sandbox, and that sandbox is fatal for OGI's own Play
# button, which runs pressure-vessel via the umu zipapp it downloads: from
# inside the appimage sandbox that chain exits with no diagnostics on OGI's
# stderr. Run unsandboxed, OGI's Play button lives in the same environment
# upstream's AppImage does on a Steam Deck.
#
# As of the fork's v4.3.1-ss.1 release, Steam-managed shortcuts no longer
# route through OGI at launch time: OGI writes the launch environment
# straight into the shortcut's `LaunchOptions` and Steam starts the game
# directly, so the sandbox question above does not apply to that path — it
# only matters for OGI's own Play button.
#
# What the AppImage carries, and why nixpkgs' Electron can run it:
#   - Electron 40.10.2 (fork's bun.lock at the pinned tag, unchanged from
#     upstream v4.3.1 for this workspace). nixpkgs marks every Electron
#     below 42 EOL and refuses to evaluate it
#     (electron/binary/generic.nix knownVulnerabilities), so electron_42 —
#     the oldest supported major at the locked nixpkgs — runs it instead.
#   - That works because `resources/app.asar` (no `app.asar.unpacked`)
#     carries only N-API native modules (utp-native, node-datachannel,
#     bufferutil, utf-8-validate, fs-native-extensions, msgpackr-extract:
#     their Linux .node files import napi_* only, no v8/node symbols), so
#     they do not depend on the Electron major. Electron unpacks .node
#     files from an asar to a temp file at load time itself.
#   - `app.isPackaged` is decided by the executable's basename, and nixpkgs'
#     binary is `electron`, so OGI would take its dev path (renderer from
#     http://localhost:8080, data dir under the store). Electron's own
#     escape hatch is the ELECTRON_FORCE_IS_PACKAGED env var
#     (shell/browser/api/electron_api_app.cc App::IsPackaged), set below.
#
# The upstream self-updater cannot work from an immutable store path; do not
# try to disable it. Updates flow through a version bump in this file instead.
#
# No log exists for any of this without help: `packages/logger/src/index.ts`
# (shockstruck/OpenGameInstaller) only ever calls `globalThis.console[...]` — it
# never opens a file. `update/latest.log`, the file the upstream UMU
# troubleshooting page (ogi.nat3z.com/docs/guide/umu) tells users to read for
# `[umu]` lines, is produced by the separate `-Setup.AppImage` Node updater
# wrapper (`updater/` in the OGI repo) capturing the app's stdout/stderr —
# this package deliberately ships the `-pt` asar without that wrapper (see
# above), so that file never exists here. Without the systemd-cat wrapper
# below, `[umu]`/`[updater]`/Electron output goes to the raw stdout/stderr of
# a process started from a `.desktop` entry or Steam shortcut and is lost the
# moment it exits. `journalctl -t opengameinstaller` is this package's
# replacement for `update/latest.log`. Nothing else is needed for winetricks
# output specifically: OGI already sets `UMU_LOG=debug` on the children it
# spawns (handler.umu.ts, initChildEnv), so the umu zipapp's own verbosity is
# already turned up — only the destination was missing.
#
# Licence: AGPL-3.0-only per the upstream LICENSE files (kept by the fork);
# application/package.json's "MIT" field is stale metadata.
#
# Pin/update path (tracks shockstruck/OpenGameInstaller fork releases, not
# Nat3z/OpenGameInstaller upstream directly — the fork's release tags are
# `v<upstream-version>-ss.<n>` prereleases, so GitHub's `/releases/latest`
# returns nothing for them):
#   1. Find the newest fork release tag:
#        gh api repos/shockstruck/OpenGameInstaller/releases --jq \
#          '[.[] | select(.tag_name | test("-ss\\."))][0].tag_name'
#   2. Bump `version` below to that tag without the leading `v`.
#   3. Refresh the hash (SRI form). Either:
#        nix store prefetch-file --json \
#          "https://github.com/shockstruck/OpenGameInstaller/releases/download/v<version>/OpenGameInstaller-linux-pt.AppImage"
#      or set `hash = lib.fakeHash;`, build once, and copy the expected hash Nix reports.
#   4. Check the Electron major in the fork's `application/package.json`
#      `electron` devDependency at the new tag (`bun.lock` at the repo root
#      is plain JSON text — grep it for `"electron@` entries, in particular
#      the `opengameinstaller-gui/electron` workspace entry) and keep the
#      `electron_<major>` argument below at or above it, within what
#      nixpkgs still supports (it refuses to evaluate EOL majors). A newer
#      Electron than the fork tested is a runtime risk, not a build failure —
#      check the window comes up.
#   5. If a release changes the internal `.desktop`/icon filenames or the Exec
#      line, update `installPhase` (the `--replace-fail` will fail loudly
#      if the Exec string drifts, which is intentional).
{ appimageTools
, electron_42
, fetchurl
, lib
, makeWrapper
, stdenvNoCC
, systemd
}:
let
  pname = "opengameinstaller";
  version = "4.3.1-ss.4";

  src = fetchurl {
    url = "https://github.com/shockstruck/OpenGameInstaller/releases/download/v${version}/OpenGameInstaller-linux-pt.AppImage";
    hash = "sha256-YfMYPOca3fW6FPUWM1B6aSapGSeoipJrIUTC1SuhbSs=";
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

    # --no-sandbox matches upstream's own desktop Exec line.
    #
    # APPIMAGE stays set even though Steam-managed shortcuts no longer start
    # OGI at all (see the header comment). getOgiExecutablePath
    # (helpers.app/platform.ts) returns $APPIMAGE, falling back to
    # process.execPath — here nixpkgs' bare electron binary, which would
    # start Electron's default app instead of OGI — and on Linux it still
    # has two readers: the per-game `.desktop` entries OGI writes under
    # ~/.local/share/applications (handler.steam.ts, `Exec="<ogi>"
    # --game-id=N`, which reaches OGI's argv parser through "$@" below), and
    # the Steam shortcut re-sync (helpers.app/steam.ts identityFor), which
    # lists the launcher as a legacy executable so a shortcut written by the
    # pre-fork package is found and rewritten rather than duplicated. Other
    # platforms still set the shortcut's Exe to it. /run/current-system/sw/bin
    # rather than $out/bin so those entries survive version bumps (this
    # package is in environment.systemPackages via
    # modules/nixos/console/launchers.nix), and Steam's own FHS env
    # bind-mounts /run so the path resolves from inside Steam too.
    #
    # Wrapping systemd-cat instead of electron directly (see the header
    # comment for why a log has to exist at all): systemd-cat's own argv
    # parsing stops at the first non-option word (systemd/src/journal/cat.c
    # parse_argv, OPTION_PARSER_STOP_AT_FIRST_NONOPTION), so `-t
    # opengameinstaller --stderr-priority=warning` are consumed as
    # systemd-cat's options and everything after — the electron path, the
    # asar, --no-sandbox, and whatever makeWrapper appends from "$@" — is
    # passed through untouched as the argv of the `execvp(args[0], args)` it
    # runs (systemd-cat(1); v241+ for --stderr-priority). OGI's own argv
    # parser sees exactly the same arguments it did before; only the process
    # that execs it changed. --stderr-priority=warning keeps stderr (Node
    # warnings, Electron's own noise) out of the default `info` stream so
    # `journalctl -p warning -t opengameinstaller` isolates real problems;
    # --priority is left at systemd-cat's default (`info`) for stdout.
    makeWrapper ${systemd}/bin/systemd-cat $out/bin/opengameinstaller \
      --add-flags "-t opengameinstaller" \
      --add-flags "--stderr-priority=warning" \
      --add-flags "${electron_42}/bin/electron" \
      --add-flags "$out/share/opengameinstaller/app.asar" \
      --add-flags "--no-sandbox" \
      --set ELECTRON_FORCE_IS_PACKAGED 1 \
      --set APPIMAGE /run/current-system/sw/bin/opengameinstaller

    runHook postInstall
  '';

  meta = {
    description = "Front-end GUI for OpenGameInstaller and the addon-server";
    homepage = "https://github.com/shockstruck/OpenGameInstaller";
    changelog = "https://github.com/shockstruck/OpenGameInstaller/releases/tag/v${version}";
    license = lib.licenses.agpl3Only;
    mainProgram = "opengameinstaller";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
