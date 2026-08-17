{ flake, pkgs, ... }:
{
  imports = [
    flake.inputs.dots-hyprland.nixosModules.default
  ];

  nixpkgs.overlays = [ flake.inputs.dots-hyprland.overlays.default ];

  services.displayManager.gdm.enable = true;
  services.displayManager.defaultSession = "hyprland";

  services.geoclue2.enable = true;
  services.gnome.gnome-keyring.enable = true;
  services.touchegg.enable = true;

  hardware.bluetooth.enable = true;
  hardware.i2c.enable = true;

  programs.dconf.enable = true;
  programs.hyprlock.enable = true;
  programs.kdeconnect.enable = true;
  programs.ydotool.enable = true;

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  programs.steam = {
    enable = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];
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

  # Terminal launched by the shared Hyprland binding. Quickshell and its
  # feature dependencies are installed by the Home Manager module.
  environment.systemPackages = [ pkgs.foot ];
}
