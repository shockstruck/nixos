{ pkgs, ... }:
{
  # The T500 is Turing (sm_75); do not compile CUDA packages for every GPU generation.
  nixpkgs.config.cudaCapabilities = [ "7.5" ];

  # Ollama's restricted service cannot load UVM itself, so make the CUDA memory
  # device available before its systemd-modules-load dependency completes.
  boot.kernelModules = [ "nvidia_uvm" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.nvidia = {
    open = false;
    modesetting.enable = true;
    powerManagement.enable = true;
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true;
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  services.ollama = {
    enable = true;
    # T500 is sm_75 (cudaCapabilities above already restricts the CUDA arch).
    # CPU set matches Tiger Lake's feature set (llama.cpp GGML_CPU_ALL_VARIANTS
    # "icelake" minus AVX512-BF16, which Tiger Lake lacks); GGML_CPU_ALL_VARIANTS
    # must be forced off or the per-target flags below are ignored.
    package = pkgs.ollama-cuda.overrideAttrs (
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
        ];
      }
    );
    loadModels = [ "nemotron-3-nano:4b" ];
    environmentVariables = {
      CUDA_VISIBLE_DEVICES = "0";
      OLLAMA_CONTEXT_LENGTH = "2048";
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KV_CACHE_TYPE = "q4_0";
    };
  };
}
