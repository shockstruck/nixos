# Callpackaged the same way modules/home/packages.nix consumes
# ../../packages/paperweight.nix.
# lutris (pkgs/by-name/lu/lutris/package.nix) and umu-launcher
# (pkgs/by-name/um/umu-launcher/package.nix) confirmed present in nixpkgs
# source at the pinned rev.
{ pkgs, ... }:
let
  opengameinstaller = pkgs.callPackage ../../../packages/opengameinstaller.nix { };
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
    # OGI addons, Lutris and umu extract RAR archives by shelling out to unrar.
    pkgs.unrar
    # OGI drives torrents through qBittorrent's WebUI API; WebUI enable and
    # password are set in-app by Kevin, never here.
    pkgs.qbittorrent
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
