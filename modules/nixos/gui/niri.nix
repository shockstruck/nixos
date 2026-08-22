{ flake, lib, pkgs, ... }:
{
  imports = [
    # niri-flake NixOS module. Provides `programs.niri`, registers the niri
    # wayland session with the display manager, wires xdg portals, polkit,
    # gnome-keyring, and the swaylock PAM entry. Predates and disables the
    # nixpkgs `programs.niri` module to avoid conflicts.
    flake.inputs.niri-flake.nixosModules.niri
  ];

  programs.niri.enable = true;
  # Use nixpkgs' maintained niri package rather than niri-flake's own
  # `make-niri`. The pinned niri-flake build references `libdisplay-info_0_2`,
  # which this repo's newer nixpkgs has removed, and the module builds niri
  # against the system nixpkgs — so overriding the package here (which also
  # propagates to the Home Manager side via the module's mkForce) is what
  # keeps evaluation working. niri-flake is still used for its typed
  # `programs.niri.settings` / `config.lib.niri.actions` interface.
  programs.niri.package = pkgs.niri;

  services.displayManager.gdm.enable = true;
  services.displayManager.defaultSession = "niri";

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
  # without this service entry, so it is required to avoid a lockout. The
  # niri-flake module also declares this; the merge is a no-op but it is kept
  # here as an explicit, self-documenting guarantee.
  security.pam.services.swaylock = { };

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

  # XWayland support under niri is provided out-of-process by
  # xwayland-satellite (niri has no built-in XWayland). It is spawned by the
  # niri session (see modules/home/niri.nix `spawn-at-startup`) on the default
  # DISPLAY, which X11 clients read to find the rootless X server.
  environment.systemPackages = [ pkgs.xwayland-satellite ];
  environment.sessionVariables.DISPLAY = ":0";
}
