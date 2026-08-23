{ lib, pkgs, ... }:
{
  services.displayManager.gdm.enable = true;
  services.displayManager.defaultSession = "hyprland";

  programs.dconf.profiles.gdm.databases = lib.mkBefore [
    {
      settings."org/gnome/desktop/peripherals/keyboard" = {
        remember-numlock-state = true;
        numlock-state = true;
      };
      locks = [
        "/org/gnome/desktop/peripherals/keyboard/remember-numlock-state"
        "/org/gnome/desktop/peripherals/keyboard/numlock-state"
      ];
    }
  ];

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

  # PAM stack for swaylock (SHOA-993). The Home Manager-installed
  # swaylock-effects cannot authenticate — and therefore cannot unlock —
  # without this service entry, so it is required to avoid a lockout.
  security.pam.services.swaylock = { };

  # Hyprland compositor (SHOA-1037, reverting the niri swap SHOA-997). Enabled
  # via the built-in nixpkgs module, which registers the `hyprland` Wayland
  # session with GDM and provides built-in XWayland (no out-of-process
  # xwayland-satellite is required, unlike niri). The Home Manager side is
  # authored in modules/home/hyprland.nix.
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
}
