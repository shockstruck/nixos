# The desktop's graphics.nix minus ROCm/OpenCL and the Ollama block: the
# console has no local-AI use case, only display output.
{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.videoDrivers = [ "amdgpu" ];
}
