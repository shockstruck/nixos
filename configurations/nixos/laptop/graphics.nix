{ lib, pkgs, ... }:

let
  # The stock `runelite` package gives its own JVM `libGL` through makeWrapper;
  # an RSPS client launched outside that wrapper has no such path. Prepend the
  # same pinned nixpkgs `libGL` (libglvnd on Linux) for one command only,
  # keeping any inherited value and never adding an empty path segment, then
  # exec the caller's exact command so Java and PRIME offload selection stay
  # with the caller. Arguments are not logged.
  rspsWithGl = pkgs.writeShellApplication {
    name = "rsps-with-gl";
    text = ''
      if [ "$#" -eq 0 ]; then
        echo "usage: rsps-with-gl <existing command and arguments>" >&2
        echo "example: rsps-with-gl java -jar /path/to/client.jar" >&2
        exit 2
      fi

      export LD_LIBRARY_PATH=${lib.makeLibraryPath [ pkgs.libGL ]}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

      exec "$@"
    '';
  };

  # The laptop's only Java 11 runtime. RSPS clients run on it and start their
  # game JVM from it, and RuneLite-based plugins load natives such as
  # `librlawt.so` that need `libGL.so.1`. Wrapping `bin/java` puts the same
  # pinned `libGL` on that process's `LD_LIBRARY_PATH`, which child JVMs
  # inherit, so an ordinary launch needs no `rsps-with-gl` prefix. The real
  # binary keeps its store path, so `java.home` still resolves to the JDK.
  temurin11WithGl = pkgs.symlinkJoin {
    name = "temurin-bin-11-with-gl";
    paths = [ pkgs.temurin-bin-11 ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/java \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ pkgs.libGL ]}
    '';
  };
in
{
  # The T500 is Turing (sm_75); do not compile CUDA packages for every GPU generation.
  nixpkgs.config.cudaCapabilities = [ "7.5" ];

  # Preload the CUDA memory device (UVM) for user CUDA applications.
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

  environment.systemPackages = [
    rspsWithGl
    temurin11WithGl
  ];
}
