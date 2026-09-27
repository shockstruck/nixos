# The desktop's graphics.nix minus ROCm/OpenCL and the Ollama block: the
# console has no local-AI use case, only display output. rocm-smi stays for
# GPU telemetry (clocks, temperature, power, VRAM); it does not enable OpenCL.
{ pkgs, ... }:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  environment.systemPackages = [ pkgs.rocmPackages.rocm-smi ];

  services.xserver.videoDrivers = [ "amdgpu" ];
}
