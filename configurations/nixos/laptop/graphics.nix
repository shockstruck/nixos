{ pkgs, ... }:

{
  # The T500 is Turing (sm_75); do not compile CUDA packages for every GPU generation.
  nixpkgs.config.cudaCapabilities = [ "7.5" ];

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
    package = pkgs.ollama-cuda;
    loadModels = [ "nemotron-3-nano:4b" ];
    environmentVariables.OLLAMA_CONTEXT_LENGTH = "4096";
  };
}
