{ flake, ... }:

{
  imports = [
    flake.inputs.nixos-hardware.nixosModules.lenovo-thinkpad
    flake.inputs.nixos-hardware.nixosModules.common-cpu-intel
    flake.inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  boot.kernelModules = [ "kvm-intel" ];

  services.fprintd.enable = true;

  # Keep sudo's password prompt immediate; GDM handles fingerprint login through
  # its dedicated parallel PAM service.
  security.pam.services.sudo.fprintAuth = false;
}
