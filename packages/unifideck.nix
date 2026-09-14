# Unifideck — a Decky Loader plugin (mubaraknumann/unifideck) bundling
# store-frontend clients (Epic/GOG/Amazon Games) as Steam shortcuts.
#
# Not built from source: upstream's own `build-plugin.sh` would separately
# download the vendored store CLIs (`legendary`, `gogdl`, `nile`, `comet`)
# this release zip already carries under `bin/`, along with a prebuilt
# `dist/` and vendored `py_modules/` (requests/vdf/websockets/…). The release
# zip is the complete, reproducible artifact; a source build would just
# re-fetch the same pieces through an unpinned script.
#
# `$out` is the plugin root itself (`$out/plugin.json` exists directly under
# `$out`) — the console module links it straight into decky-loader's
# `plugins/` directory via `systemd.tmpfiles.settings`.
#
# `bin/legendary`, `bin/gogdl` and `bin/unifideck-launcher` are
# `#!/usr/bin/env python3` scripts patched by `patchShebangs` (hence
# `python3` in `nativeBuildInputs`, used only to resolve that shebang, not as
# a runtime dependency); `bin/nile` and `bin/comet` are glibc ELF binaries
# left untouched (`dontPatchELF`) — the console module enables `nix-ld` so
# they resolve their dynamic loader and libraries at runtime instead.
#
# Pin/update path:
#   1. Find the newest release tag:
#        curl -s https://api.github.com/repos/mubaraknumann/unifideck/releases/latest | jq -r .tag_name
#   2. Bump `version` below to the release's asset version
#      (`unifideck.prod.v<version>.zip`).
#   3. Refresh the hash (SRI form). Either:
#        nix store prefetch-file --json \
#          "https://github.com/mubaraknumann/unifideck/releases/download/Release-<tag>/unifideck.prod.v<version>.zip"
#      or set `hash = lib.fakeHash;`, build once, and copy the expected hash
#      Nix reports. (`sha256sum` + `python3 -c "import base64; ..."` also
#      derives the SRI form directly from the release asset without
#      realising anything.)
{ lib
, stdenv
, fetchurl
, unzip
, python3
}:
stdenv.mkDerivation {
  pname = "unifideck";
  version = "0.7.5";

  src = fetchurl {
    url = "https://github.com/mubaraknumann/unifideck/releases/download/Release-0.7.5/unifideck.prod.v0.7.5.zip";
    hash = "sha256-/S/AvpSLHfNmKjeajpP+tGNpEmMSiO5QTfFkx3Glxzg=";
  };

  sourceRoot = "Unifideck";

  nativeBuildInputs = [ unzip python3 ];

  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r . $out

    runHook postInstall
  '';

  meta = {
    description = "Decky Loader plugin unifying non-Steam store clients (Epic, GOG, Amazon Games) as Steam shortcuts";
    homepage = "https://github.com/mubaraknumann/unifideck";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.gpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
