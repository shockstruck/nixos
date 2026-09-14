{ pkgs, ... }:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # ROCm OpenCL (SHOC-46): amdgpu.nix wires rocmPackages.clr + clr.icd into
  # hardware.graphics.extraPackages for us.
  hardware.amdgpu.opencl.enable = true;

  # Verified in nixpkgs nixos/modules/services/hardware/lact.nix at the locked
  # rev ef34387d: `services.lact.enable` (mkEnableOption) installs the `lact`
  # package and enables the `lactd` daemon; the overdrive bit it needs comes
  # from ./hardware.nix.
  services.lact.enable = true;

  environment.systemPackages = [
    pkgs.rocmPackages.rocm-smi
    pkgs.rocmPackages.rocminfo
  ];

  services.xserver.videoDrivers = [ "amdgpu" ];

  services.ollama = {
    enable = true;
    package = pkgs.ollama-rocm;
    loadModels = [ "qwen3.5:9b" ];
    environmentVariables = {
      OLLAMA_CONTEXT_LENGTH = "4096";
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KV_CACHE_TYPE = "q8_0";
    };
  };

  systemd.services.ollama.serviceConfig = {
    Restart = "on-failure";
    RestartSec = "5s";
  };
}
