# This is your nixos configuration.
# For home configuration, see /modules/home/*
{ flake, ... }:
{
  imports = [
    flake.inputs.self.nixosModules.common
  ];

  hardware.enableRedistributableFirmware = true;
  networking.networkmanager.enable = true;
  nixpkgs.config.allowUnfree = true;
  services.openssh.enable = true;
  zramSwap.enable = true;
}
