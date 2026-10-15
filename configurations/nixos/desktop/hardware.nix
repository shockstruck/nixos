{ flake, lib, pkgs, ... }:

let
  # Navi 31 (RX 7900 XT/XTX) graphics microcode, ME/MEC/MES/PFP, from
  # linux-firmware commit 9a7c283f, AMD's revert of the GC 11.0.0 updates
  # of 2026-08-10 (59ab5359) and 2026-09-11 (cd0c6107): "Causes instability
  # in some games" — `Illegal opcode in command stream` on gfx_0.0.0, a
  # failed MES ring reset and a MODE1 GPU reset mid-game. The blobs are
  # byte-identical to linux-firmware 20260622. nixpkgs' linux-firmware
  # 20260916 still carries the reverted ones; drop this block once nixpkgs
  # ships a linux-firmware tag newer than 20260916.
  linuxFirmwareRev = "9a7c283fa0037c4db360214192d57aab1272d403";
  gc1100Blobs = {
    me = "sha256-8nTcRFKddJsan6BidrjzKilooWroAYlr0RxTsjTMjhs=";
    mec = "sha256-2lkD0NEVZvTICKi56PerugqGlZYQ5fWY1Qjr0V0dPug=";
    mes1 = "sha256-h0DZo7zc0L4PBILsfbeQB6EaboNXqpV2cyhssT342sA=";
    mes_2 = "sha256-0p6vC5mvg3hfnYz+POeR8PsepCay9fCnVqUNPtsGyVc=";
    pfp = "sha256-1Xs0or1FwclEg03xZlVhL1s+NPWWScqxOMwwlYkfYbM=";
  };
  fetchGc1100Blob = name: hash: pkgs.fetchurl {
    url = "https://gitlab.com/kernel-firmware/linux-firmware/-/raw/${linuxFirmwareRev}/amdgpu/gc_11_0_0_${name}.bin";
    inherit hash;
  };
  copyGc1100Blobs = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: hash: "cp ${fetchGc1100Blob name hash} $out/lib/firmware/amdgpu/gc_11_0_0_${name}.bin") gc1100Blobs);
  gc1100Firmware = pkgs.runCommand "amdgpu-gc-11.0.0-firmware" { } ''
    mkdir -p $out/lib/firmware/amdgpu
    ${copyGc1100Blobs}
  '';
in
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
  # line reaches desktop and console: the desktop for the LACT daemon
  # (services.lact.enable in ./graphics.nix), the console for
  # steamos-manager's GPU clock control (modules/nixos/console/
  # steamos-manager.nix writes pp_od_clk_voltage, which needs this mask).
  hardware.amdgpu.overdrive.enable = true;

  # nixos/modules/services/hardware/udev.nix: `hardware.firmware` is one
  # buildEnv with ignoreCollisions, "the first package in the list takes
  # precedence", and linux-firmware sets meta.priority = 6 (kept through
  # compressFirmware) so any default-priority package shadows its files.
  # Only these five files change; every other blob stays linux-firmware's.
  # Reaches desktop and console (both Navi 31), never laptop.
  hardware.firmware = lib.mkBefore [ gc1100Firmware ];

  # Verified against nixpkgs source before writing:
  #   nixos/modules/services/hardware/openrgb.nix: `enable` is mkEnableOption;
  #     `motherboard` is `nullOr (enum ["amd" "intel"])`, defaulting to "amd" on
  #     these hosts anyway via hardware.cpu.amd.updateMicrocode (set by
  #     nixos-hardware's common-cpu-amd from hardware.enableRedistributableFirmware
  #     = true) — pinned explicitly so the i2c-piix4 module load does not depend
  #     on that chain. The module adds `openrgb` to environment.systemPackages
  #     and services.udev.packages, loads i2c-dev + i2c-piix4, and runs
  #     `openrgb --server --server-port 6742` as systemd.services.openrgb
  #     (Restart = "always", StateDirectory = OpenRGB).
  # Imported by path into `console` too (../console/default.nix), so this one
  # block reaches desktop and console, never laptop.
  services.hardware.openrgb = {
    enable = true;
    motherboard = "amd";
  };
}
