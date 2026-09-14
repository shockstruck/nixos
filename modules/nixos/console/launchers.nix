# Callpackaged the same way modules/home/packages.nix consumes
# ../../packages/paperweight.nix.
# lutris (pkgs/by-name/lu/lutris/package.nix) and umu-launcher
# (pkgs/by-name/um/umu-launcher/package.nix) confirmed present in nixpkgs
# source at the pinned rev.
{ pkgs, ... }:
let
  opengameinstaller = pkgs.callPackage ../../../packages/opengameinstaller.nix { };

  # fatboy-unpack (OGI's FitGirl addon) extracts a FuckingFast download by
  # running `unrar x <partN.rar> <dir> -idn -kb -y` once per downloaded
  # volume, sequentially, and fails the whole setup on any non-zero exit.
  # The first run already extracts the entire set (unrar follows
  # part0 -> part1 -> ...); every later run starts on a non-first volume
  # whose first entry continues from the previous one, so unrar prints
  # "You need to start extraction from a previous volume to unpack ..."
  # (loclang.hpp MUnpCannotMerge) and exits 6 (errhnd.hpp RARX_OPEN), which
  # the addon reports as "Failed to extract downloaded files" even though
  # the repack is fully on disk. This wrapper reports success for exactly
  # that case and only for that call signature; anything else — other
  # commands, other switches, other exit codes, other messages — is passed
  # through untouched, so Lutris and umu see the real unrar. Stdout is not
  # intercepted: the addon parses its progress from it. Upstream fix is a
  # one-liner in the addon (extract the first volume only); remove this
  # once it lands.
  unrarFatboy = pkgs.writeShellApplication {
    name = "unrar";
    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep ];
    text = ''
      if [ "$#" -lt 6 ] || [ "$1" != "x" ] \
        || [ "''${*: -3:1}" != "-idn" ] || [ "''${*: -2:1}" != "-kb" ] || [ "''${*: -1}" != "-y" ]; then
        exec ${pkgs.unrar}/bin/unrar "$@"
      fi
      stderr_file="$(mktemp)"
      trap 'rm -f "$stderr_file"' EXIT
      set +e
      ${pkgs.unrar}/bin/unrar "$@" 2> "$stderr_file"
      code=$?
      set -e
      cat "$stderr_file" >&2
      if [ "$code" -eq 6 ] && grep -q 'You need to start extraction from a previous volume' "$stderr_file"; then
        echo "unrar (console wrapper): non-first volume already extracted with its first volume; reporting success" >&2
        exit 0
      fi
      exit "$code"
    '';
  };
in
{
  environment.systemPackages = [
    pkgs.heroic
    pkgs.protonup-qt
    pkgs.mangohud
    pkgs.lutris
    pkgs.umu-launcher
    opengameinstaller
    # OGI's NixOS branch expects Bun on PATH and offers no installer of its own.
    pkgs.bun
    # OGI addons, Lutris and umu extract RAR archives by shelling out to unrar; see unrarFatboy above for why this is a wrapper.
    unrarFatboy
    # OGI does not use the umu-launcher above for its own Windows-game flow:
    # it downloads the upstream umu zipapp to
    # ~/.local/share/OpenGameInstaller/bin/umu/umu-run (application/src/
    # electron/startup.ts, handlers/handler.umu.ts) and addons spawn it
    # directly for setup.exe / winetricks. That zipapp is a `python3` script
    # (umu-launcher Makefile.in, `python3 -m zipapp … -p`) with pure-Python
    # deps, and the AppImage FHS env OGI runs in carries no interpreter
    # (appimageTools.defaultFhsEnvArgs), so it resolves `python3` from the
    # host PATH — absent here until this line.
    pkgs.python3
  ];

  # genesis-lib, the OGI addon library behind Cloudflare/DDoS-Guard bypass and
  # the file-host downloaders, resolves its Chromium path on Linux only via
  # `flatpak info --show-location` on this Flathub app id (lib/config.ts); a
  # nixpkgs `chromium` or the console's Brave does not satisfy it, so the
  # addon shows its "install from Flathub" slide without this. Copy of the
  # grayjay-flatpak service in gui/hyprland.nix, not an import.
  systemd.services.chromium-flatpak = {
    description = "Install or update Chromium from Flathub";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      ${pkgs.flatpak}/bin/flatpak remote-add --system --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo

      if ${pkgs.flatpak}/bin/flatpak info --system org.chromium.Chromium >/dev/null 2>&1; then
        ${pkgs.flatpak}/bin/flatpak update --system --noninteractive org.chromium.Chromium
      else
        ${pkgs.flatpak}/bin/flatpak install --system --noninteractive flathub org.chromium.Chromium
      fi
    '';
  };
}
