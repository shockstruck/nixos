# Libvirt/QEMU virtualisation and Cockpit (SHOC-46). Desktop only — nothing
# here touches modules/, so the laptop is unaffected.
{ config, lib, pkgs, ... }:
{
  virtualisation.libvirtd = {
    enable = true;
    qemu.ovmf.enable = true;
  };

  programs.virt-manager.enable = true;

  # Group membership lives here, not in modules/nixos/common/myusers.nix:
  # that module is shared, and adding "libvirtd" there would put a group
  # reference on the laptop that has no group behind it.
  users.users = lib.genAttrs config.myusers (_: { extraGroups = [ "libvirtd" ]; });

  services.cockpit = {
    enable = true;
    plugins = with pkgs; [ cockpit-machines cockpit-files cockpit-dockermanager ];
    # openFirewall is left at its default (false). Cockpit is a root-capable
    # web admin console; firewall policy is Security Identity's domain, and
    # Kevin approved the feature, not a network-exposed port. Reach it via
    # https://localhost:9090 or an SSH tunnel.
  };
}
