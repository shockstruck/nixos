{ pkgs, ... }:
{
  # Noctalia greeter (greetd) is the display manager (SHOA-1040, replacing GDM):
  # nixpkgs' `services.displayManager.noctalia-greeter` module enables greetd
  # and the auto-created `greeter` user, and the greeter selects the `niri`
  # session, the only session package left once programs.niri below replaces
  # programs.hyprland. The cursor matches home.pointerCursor
  # (modules/home/theme/nullscapes.nix).
  services.displayManager.noctalia-greeter = {
    enable = true;
    cursorTheme = {
      package = pkgs.catppuccin-cursors.mochaDark;
      name = "catppuccin-mocha-dark-cursors";
    };
    settings.keyboard.layout = "us";
  };

  services.geoclue2.enable = true;
  services.accounts-daemon.enable = true;
  services.flatpak.enable = true;
  services.gnome.gnome-keyring.enable = true;
  services.gvfs.enable = true;
  services.udisks2.enable = true;

  # Nautilus loads its extension modules from NAUTILUS_4_EXTENSION_DIR
  # (nixpkgs' extension_dir.patch). Pointing it at nautilus-python lets the
  # Nextcloud client's Python extension (modules/home/nextcloud.nix) load
  # from $XDG_DATA_DIRS/nautilus-python/extensions. Same wiring as nixpkgs'
  # programs.nautilus-open-any-terminal module.
  environment.sessionVariables.NAUTILUS_4_EXTENSION_DIR = "${pkgs.nautilus-python}/lib/nautilus/extensions-4";

  hardware.bluetooth.enable = true;
  hardware.i2c.enable = true;

  programs.dconf.enable = true;
  programs.kdeconnect.enable = true;
  security.polkit.enable = true;

  # niri compositor, enabled via the built-in nixpkgs module
  # (nixos/modules/programs/wayland/niri.nix): it installs niri, registers the
  # `niri` session (niri-session -> niri.service, which binds
  # graphical-session.target), defaults the display manager session to it,
  # and sets up the gnome/gtk portals and gnome-keyring niri recommends. niri
  # has no built-in XWayland; it starts xwayland-satellite on demand when that
  # is on PATH, which the Home Manager side (modules/home/niri.nix) installs.
  # No per-locker PAM entry is needed: Noctalia's lock screen authenticates
  # via the standard `login` PAM service.
  programs.niri.enable = true;

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
