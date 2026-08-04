{ flake, ... }:

{
  imports = [
    flake.inputs.nixos-hardware.nixosModules.common-cpu-amd
    flake.inputs.nixos-hardware.nixosModules.common-gpu-amd
    flake.inputs.nixos-hardware.nixosModules.common-pc
    flake.inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  boot.kernelModules = [ "kvm-amd" ];
}
