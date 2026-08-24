{ flake, pkgs, ... }:

{
  imports = [
    flake.inputs.nixos-hardware.nixosModules.lenovo-thinkpad
    flake.inputs.nixos-hardware.nixosModules.common-cpu-intel
    flake.inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  boot.kernelModules = [ "kvm-intel" ];

  services.fprintd.enable = true;

  # Fingerprint auth (founder-directed, SHOA-1075). With services.fprintd.enable,
  # NixOS makes fprint a *sufficient* PAM factor for the greetd/Noctalia login
  # (GDM was retired in SHOA-1040) and polkit, so a swipe unlocks but the password
  # prompt still works as fallback — no lockout. The founder also asked for
  # fingerprint at sudo, so enable it here; it stays a sufficient factor, so sudo
  # falls back to the password when no finger is enrolled or the swipe fails.
  # Enroll with `fprintd-enroll` (see README) before relying on it.
  security.pam.services.sudo.fprintAuth = true;

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
