{ flake, ... }:

let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    self.nixosModules.default
    self.nixosModules.gui
    inputs.disko.nixosModules.disko
    ./boot.nix
    ./hardware.nix
    ./graphics.nix
    ./power.nix
    ./storage.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "laptop";
  system.stateVersion = "24.11";
}
