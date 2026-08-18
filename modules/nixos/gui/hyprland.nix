{ pkgs, ... }:
{
  services.displayManager.gdm.enable = true;
  services.displayManager.defaultSession = "hyprland";

  services.geoclue2.enable = true;
  services.accounts-daemon.enable = true;
  services.flatpak.enable = true;
  services.gnome.gnome-keyring.enable = true;
  services.gvfs.enable = true;
  services.udisks2.enable = true;

  hardware.bluetooth.enable = true;
  hardware.i2c.enable = true;

  programs.dconf.enable = true;
  programs.kdeconnect.enable = true;
  security.polkit.enable = true;

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  programs.steam = {
    enable = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };

  systemd.services.grayjay-flatpak = {
    description = "Install or update Grayjay from Flathub";
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

      if ${pkgs.flatpak}/bin/flatpak info --system app.grayjay.Grayjay >/dev/null 2>&1; then
        ${pkgs.flatpak}/bin/flatpak update --system --noninteractive app.grayjay.Grayjay
      else
        ${pkgs.flatpak}/bin/flatpak install --system --noninteractive flathub app.grayjay.Grayjay
      fi
    '';
  };

  environment.pathsToLink = [ "/share/applications" "/share/xdg-desktop-portal" ];

  fonts.packages = [
    (pkgs.google-fonts.override {
      fonts = [ "Google Sans Flex" "Readex Pro" "Space Grotesk" ];
    })
    pkgs.material-symbols
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.rubik
    pkgs.twemoji-color-font
  ];

  # Terminal launched by the shared Hyprland binding. DMS and its feature
  # dependencies are installed by the Home Manager module.
  environment.systemPackages = [ pkgs.foot ];
}
