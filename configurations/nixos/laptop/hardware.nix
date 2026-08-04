{ flake, ... }:

{
  imports = [
    flake.inputs.nixos-hardware.nixosModules.lenovo-thinkpad
    flake.inputs.nixos-hardware.nixosModules.common-cpu-intel
    flake.inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  boot.kernelModules = [ "kvm-intel" ];
}
