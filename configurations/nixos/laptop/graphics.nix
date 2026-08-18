{ config, lib, pkgs, ... }:

let
  ollamaCudaLibrary = "cuda_v${lib.versions.major pkgs.cudaPackages.cuda_cudart.version}";
  waitForNvidia = pkgs.writeShellScript "wait-for-nvidia" ''
    for attempt in {1..30}; do
      if ${config.hardware.nvidia.package}/bin/nvidia-smi -L >/dev/null 2>&1; then
        exit 0
      fi
      sleep 1
    done

    echo "NVIDIA GPU did not become ready before Ollama startup" >&2
    exit 1
  '';
in
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
    package = pkgs.ollama-cuda;
    loadModels = [ "nemotron-3-nano:4b" ];
    environmentVariables = {
      CUDA_VISIBLE_DEVICES = "0";
      OLLAMA_CONTEXT_LENGTH = "2048";
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KV_CACHE_TYPE = "q4_0";
      OLLAMA_LLM_LIBRARY = ollamaCudaLibrary;
    };
  };

  systemd.services.ollama = {
    wants = [ "systemd-modules-load.service" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      ExecStartPre = waitForNvidia;
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
