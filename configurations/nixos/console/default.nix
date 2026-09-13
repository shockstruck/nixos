# The console is a hardware variant of the desktop (same AMD CPU/GPU, single
# NVMe, LUKS2/TPM2 disko layout), so its boot, hardware, power and storage
# truth is imported by path from ../desktop/ rather than copied. A console on
# different hardware would replace those four imports with local files.
{ flake, ... }:

let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    self.nixosModules.default
    self.nixosModules.console
    inputs.disko.nixosModules.disko
    ../desktop/boot.nix
    ../desktop/hardware.nix
    ../desktop/power.nix
    ../desktop/storage.nix
    ./graphics.nix
  ];

  myhome.dir = self + /configurations/home/console;

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "console";

  # New host, first installed on this channel — deliberately not the
  # desktop/laptop's "24.11".
  system.stateVersion = "26.05";
}
