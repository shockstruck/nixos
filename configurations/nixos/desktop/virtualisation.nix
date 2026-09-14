# Libvirt/QEMU virtualisation and Cockpit (SHOC-46). Desktop only — nothing
# here touches modules/, so the laptop is unaffected. The Looking Glass
# client itself is a Home Manager package (modules/home/packages.nix, both
# hosts); this file only carries the host-side kvmfr plumbing a VM guest
# needs to hand frames back to it.
{ config, lib, pkgs, ... }:
{
  virtualisation.libvirtd.enable = true;

  programs.virt-manager.enable = true;

  # Group membership lives here, not in modules/nixos/common/myusers.nix:
  # that module is shared, and adding "libvirtd" there would put a group
  # reference on the laptop that has no group behind it.
  users.users = lib.genAttrs config.myusers (_: { extraGroups = [ "libvirtd" ]; });

  # kvmfr: shared-memory frame transport for the Looking Glass client
  # (modules/home/packages.nix) to read a VM guest's framebuffer without a
  # network hop.
  boot.extraModulePackages = [ config.boot.kernelPackages.kvmfr ];
  boot.kernelModules = [ "kvmfr" ];
  # 128 MiB covers a 3840x2160 SDR frame (Looking Glass sizing formula:
  # w*h*4*2/MiB + 10, rounded up to a power of two). The guest's libvirt
  # <shmem> device size must match this exactly, or Looking Glass refuses to
  # attach.
  boot.extraModprobeConfig = "options kvmfr static_size_mb=128";
  # Same seat-user grant pattern as the ntsync rule in
  # modules/nixos/console/performance.nix.
  services.udev.extraRules = ''
    SUBSYSTEM=="kvmfr", GROUP="kvm", MODE="0660", TAG+="uaccess"
  '';

  virtualisation.libvirtd.qemu.verbatimConfig = ''
    # namespaces = [] is nixpkgs' own default for this option, but setting
    # verbatimConfig at all replaces rather than merges it, so it has to be
    # repeated here or QEMU would pick up namespaces we don't want.
    namespaces = []
    cgroup_device_acl = [ "/dev/null", "/dev/full", "/dev/zero", "/dev/random", "/dev/urandom", "/dev/ptmx", "/dev/kvm", "/dev/rtc", "/dev/hpet", "/dev/vfio/vfio", "/dev/kvmfr0" ]
  '';

  services.cockpit = {
    enable = true;
    plugins = with pkgs; [ cockpit-machines cockpit-files cockpit-dockermanager ];
    # openFirewall is left at its default (false). Cockpit is a root-capable
    # web admin console; firewall policy is Security Identity's domain, and
    # Kevin approved the feature, not a network-exposed port. Reach it via
    # https://localhost:9090 or an SSH tunnel.
  };
}
