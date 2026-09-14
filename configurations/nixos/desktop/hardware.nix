{ flake, ... }:

{
  imports = [
    flake.inputs.nixos-hardware.nixosModules.common-cpu-amd
    flake.inputs.nixos-hardware.nixosModules.common-gpu-amd
    flake.inputs.nixos-hardware.nixosModules.common-pc
    flake.inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  boot.kernelModules = [ "kvm-amd" ];

  # Verified against nixpkgs source before writing:
  #   nixos/modules/services/hardware/amdgpu.nix: `hardware.amdgpu.overdrive.enable`
  #     (mkEnableOption) appends `amdgpu.ppfeaturemask=${cfg.overdrive.ppfeaturemask}`
  #     to boot.kernelParams; default mask "0xfffd7fff" (amdgpu's default
  #     0xfffd3fff with LACT's PP_OVERDRIVE_MASK 0x4000 set).
  #   nixos/modules/services/hardware/lact.nix recommends exactly this option.
  # Imported by path into `console` too (../console/default.nix), so this one
  # line reaches desktop and console, the two hosts that run the LACT daemon
  # (services.lact.enable: desktop in ./graphics.nix, console in
  # modules/nixos/console/performance.nix).
  hardware.amdgpu.overdrive.enable = true;
}
