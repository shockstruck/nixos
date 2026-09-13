# Verified against nixpkgs source before writing:
#   nixos/modules/programs/steam.nix:
#     gamescopeSession.enable — a submodule option under programs.steam.
#     protontricks.enable — lib.mkEnableOption "protontricks, a simple
#       wrapper for running Winetricks commands for Proton-enabled games".
#   nixos/modules/services/display-managers/greetd.nix:
#     settings.initial_session is referenced directly by the module
#     (`default = !(cfg.settings ? initial_session);`); settings is a
#     freeform submodule passed through to greetd's TOML config, so
#     default_session is the standard companion key from greetd's own
#     schema rather than a separately declared nix option.
#   nixos/modules/services/desktops/pipewire/pipewire.nix:
#     enable, alsa.enable, alsa.support32Bit, pulse.enable all declared.
#   nixos/modules/security/rtkit.nix: enable declared.
#   nixos/modules/services/desktops/flatpak.nix: asserts xdg.portal.enable.
#   nixos/modules/config/xdg/portal.nix: enable, extraPortals (asserted
#     non-empty when enabled), config (attrsOf (attrsOf (str | listOf str))).
{ config, lib, pkgs, ... }:

{
  programs.steam = {
    enable = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];
    protontricks.enable = true;
    gamescopeSession.enable = true;
  };

  # initial_session boots straight into Steam once; when Steam exits, greetd
  # falls to default_session, a text greeter that relaunches Steam on login
  # instead of crash-looping the autologin. steam-gamescope is the wrapper
  # nixpkgs installs into environment.systemPackages when
  # programs.steam.gamescopeSession.enable is true.
  services.greetd = {
    enable = true;
    settings = {
      initial_session = {
        command = "${config.system.path}/bin/steam-gamescope";
        user = builtins.head config.myusers;
      };
      default_session = {
        command = "${lib.getExe pkgs.tuigreet} --cmd ${config.system.path}/bin/steam-gamescope";
        user = "greeter";
      };
    };
  };

  # The desktop gets audio through its own gui module; the console has no gui
  # module, so it needs its own pipewire/rtkit stack.
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;

  hardware.bluetooth.enable = true;
  services.flatpak.enable = true;
  security.polkit.enable = true;
  programs.dconf.enable = true;

  # services.flatpak asserts xdg.portal.enable. On desktop/laptop
  # programs.hyprland turns the portal on and supplies its own backend; the
  # console has no compositor module, so it carries the generic GTK backend.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = [ "gtk" ];
  };
}
