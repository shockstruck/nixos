{ pkgs, ... }:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

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
