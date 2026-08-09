{ flake, pkgs, ... }:
{
  imports = [
    flake.inputs.vast-shell.nixosModules.default
  ];

  services.displayManager.gdm.enable = true;
  services.displayManager.defaultSession = "hyprland";

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # Terminal launched by the shared Hyprland binding.
  environment.systemPackages = [ pkgs.foot ];

  # Started by vast-shell's upstream quickshell-shell.service; do not add a
  # second autostart path.
  programs.quickshell-shell.enable = true;
}
