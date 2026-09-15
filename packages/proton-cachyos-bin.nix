# Proton-CachyOS — CachyOS's Proton fork (FSR 4/OptiScaler auto-injection,
# a newer Wine base). Not in nixpkgs (no `proton-cachyos` attribute exists
# upstream); CachyOS's own release only ships prebuilt tarballs, no source
# build is offered.
#
# Nix-built rather than the ProtonUp-Qt route already on the console
# (`modules/nixos/console/launchers.nix`): ProtonUp-Qt drops the tool into
# the user's mutable `~/.local/share/Steam/compatibilitytools.d/`, which
# only Steam and manual per-game pickers see. A store path, by contrast, can
# be set once as `environment.sessionVariables.PROTONPATH`
# (`console/launchers.nix`) and becomes the default Proton for every
# umu-launcher invocation — including OpenGameInstaller's, which spawns
# `umu-run` with a spread of `process.env` and only overrides `PROTONPATH`
# per-game when a game has its own `protonVersion` set
# (`application/src/electron/handlers/helpers.app/umu-environment.ts`,
# upstream Nat3z/OpenGameInstaller). That is what makes the umu default
# declarative instead of a manual ProtonUp-Qt install repeated after every
# reinstall.
#
# `x86_64_v3`: the console is the desktop's Zen 4 class, which is
# v3-capable, and ProtonUp-Qt's own Proton-CachyOS installer
# (`pupgui2/resources/ctmods/ctmod_protoncachyos.py`) picks the same
# `x86_64_v3` asset whenever the host's hwcaps allow it. Fall back to the
# plain `x86_64` release asset (drop `_v3` from `toolName` below) on
# non-v3-capable hardware.
#
# FSR4/OptiScaler never write into the tool directory: OptiScaler's upscaler
# downloads land in `$XDG_CACHE_HOME/protonfixes/upscalers`, and
# `PROTON_USE_OPTISCALER`/`PROTON_FSR4_UPGRADE` state lands in the Wine
# prefix's `drive_c/windows/system32/umu/` (`protonfixes/upscalers.py`,
# `protonfixes/config.py`, upstream Open-Wine-Components/umu-launcher). A
# read-only Nix store path for the tool itself is therefore fine, the same
# as nixpkgs' own `proton-ge-bin`.
#
# `dontConfigure`/`dontBuild`/`dontFixup`: fixup's binary stripping and
# shebang patching would corrupt the Wine binaries and the scripts meant to
# run inside umu/Steam's pressure-vessel container, not on the host — the
# same reason `proton-ge-bin` skips fixup.
#
# Pin/update path:
#   1. Find the newest `cachyos-*-slr` tag:
#        curl -s https://api.github.com/repos/CachyOS/proton-cachyos/releases/latest | jq -r .tag_name
#   2. Bump `version` below to the tag with the leading `cachyos-` and
#      trailing `-slr` stripped.
#   3. Take the hex digest from that release's `.sha512sum` asset and
#      convert it to SRI:
#        python3 -c 'import base64,sys;print("sha512-"+base64.b64encode(bytes.fromhex(sys.argv[1])).decode())' <hex>
{ lib
, stdenvNoCC
, fetchurl
}:
let
  pname = "proton-cachyos-bin";
  version = "11.0-20260703";
  toolName = "proton-cachyos-${version}-slr-x86_64_v3";

  src = fetchurl {
    url = "https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-${version}-slr/${toolName}.tar.xz";
    hash = "sha512-WRGoYLDdESaPNzbTMoenSZOt2pjkyURNFc+fiYj86pwdk6AeFNEBkCFFit0XVQlev2wqglyg1JzjSbNbF5zQEw==";
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  outputs = [ "out" "steamcompattool" ];

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/doc/${pname}
    echo "Proton-CachyOS ${version}, packaged in $steamcompattool" > $out/share/doc/${pname}/README

    mkdir -p $steamcompattool
    cp -a . $steamcompattool/

    substituteInPlace $steamcompattool/compatibilitytool.vdf \
      --replace-fail "${toolName}" "Proton-CachyOS"

    runHook postInstall
  '';

  meta = {
    description = "CachyOS's Proton fork with FSR 4 / OptiScaler auto-injection support";
    homepage = "https://github.com/CachyOS/proton-cachyos";
    changelog = "https://github.com/CachyOS/proton-cachyos/releases/tag/cachyos-${version}-slr";
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
