# This is your nixos configuration.
# For home configuration, see /modules/home/*
{ flake, pkgs, ... }:
{
  imports = [
    flake.inputs.self.nixosModules.common
    ./multica.nix
    ./opencode-policy.nix
  ];

  hardware.enableRedistributableFirmware = true;
  environment.systemPackages = [
    pkgs.docker-compose
    # Hardware inspection on every host: lspci, lsusb, sensors.
    pkgs.lm_sensors
    pkgs.pciutils
    pkgs.usbutils
  ];
  networking.networkmanager.enable = true;
  # Pin as a list: nixos-unified's mkDefault sets this as a string, which no longer type-checks.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;
  services.netbird.enable = true;
  services.openssh.enable = true;
  time.timeZone = "America/Detroit";
  virtualisation.docker.enable = true;
  zramSwap.enable = true;
}
