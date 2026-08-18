{ flake, pkgs, ... }:

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

  systemd.services.keyboard-backlight-default = {
    description = "Enable the ThinkPad keyboard backlight after boot";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-backlight@leds:tpacpi::kbd_backlight.service" ];
    unitConfig.ConditionPathExists = "/sys/class/leds/tpacpi::kbd_backlight/brightness";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.brightnessctl}/bin/brightnessctl --device=tpacpi::kbd_backlight set 100%";
    };
  };
}
