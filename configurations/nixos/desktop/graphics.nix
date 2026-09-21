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
    # RX 7900 XT = Navi 31 = gfx1100; upstream nixpkgs ollama otherwise builds
    # all 16 rocmPackages.clr.gpuTargets. CPU set matches the 7950X's Zen 4
    # feature set (llama.cpp GGML_CPU_ALL_VARIANTS "zen4"); GGML_CPU_ALL_VARIANTS
    # must be forced off or the per-target flags below are ignored.
    package = (pkgs.ollama-rocm.override { rocmGpuTargets = [ "gfx1100" ]; }).overrideAttrs (
      prev: {
        cmakeFlags = (prev.cmakeFlags or [ ]) ++ [
          "-DGGML_CPU_ALL_VARIANTS=OFF"
          "-DGGML_SSE42=ON"
          "-DGGML_AVX=ON"
          "-DGGML_F16C=ON"
          "-DGGML_FMA=ON"
          "-DGGML_AVX2=ON"
          "-DGGML_BMI2=ON"
          "-DGGML_AVX512=ON"
          "-DGGML_AVX512_VBMI=ON"
          "-DGGML_AVX512_VNNI=ON"
          "-DGGML_AVX512_BF16=ON"
        ];
      }
    );
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
