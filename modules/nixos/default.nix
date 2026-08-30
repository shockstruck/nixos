# This is your nixos configuration.
# For home configuration, see /modules/home/*
{ flake, pkgs, ... }:
{
  imports = [
    flake.inputs.self.nixosModules.common
  ];

  hardware.enableRedistributableFirmware = true;
  environment.systemPackages = [ pkgs.docker-compose ];
  networking.networkmanager.enable = true;
  nixpkgs.config.allowUnfree = true;
  # eBPF tracing tools (SHOC-46): wires bcc into both environment.systemPackages
  # and boot.extraModulePackages, which home.packages cannot do.
  programs.bcc.enable = true;
  services.netbird.enable = true;
  services.openssh.enable = true;
  time.timeZone = "America/Detroit";
  virtualisation.docker.enable = true;
  zramSwap.enable = true;
}
