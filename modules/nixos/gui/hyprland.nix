{ pkgs, ... }:
{
  # Noctalia greeter (greetd) is the display manager (SHOA-1040, replacing GDM):
  # nixpkgs' `services.displayManager.noctalia-greeter` module enables greetd
  # and the auto-created `greeter` user, and the greeter selects the `hyprland`
  # session. Adwaita cursor matches home.pointerCursor (modules/home/hyprland.nix).
  services.displayManager.noctalia-greeter = {
    enable = true;
    cursorTheme = {
      package = pkgs.adwaita-icon-theme;
      name = "Adwaita";
    };
    settings.keyboard.layout = "us";
  };

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

  # Hyprland compositor (SHOA-1037, reverting the compositor swap SHOA-997). Enabled
  # via the built-in nixpkgs module, which provides built-in XWayland (no
  # out-of-process xwayland-satellite is required, unlike the previous compositor). The Home
  # Manager side is authored in modules/home/hyprland.nix. No per-locker PAM
  # entry is needed: Noctalia's lock screen authenticates via the standard
  # `login` PAM service (SHOA-1026/1040), so the removed legacy locker PAM entry has
  # no replacement.
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
    pkgs.cascadia-code
  ];
}
