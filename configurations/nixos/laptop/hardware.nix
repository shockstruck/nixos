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

  # The ThinkPad forgets the keyboard-backlight level across suspend, so save the
  # LED's raw sysfs value before sleep and replay it when the machine wakes. The
  # value can legitimately be 0, so the saved file's presence, not its content,
  # decides whether there is anything to restore.
  systemd.services.keyboard-backlight-sleep = {
    description = "Save and restore the ThinkPad keyboard backlight across sleep";
    wantedBy = [ "sleep.target" ];
    before = [ "sleep.target" ];
    unitConfig.StopWhenUnneeded = true;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "keyboard-backlight";
    };
    script = ''
      led=/sys/class/leds/tpacpi::kbd_backlight/brightness
      state="$RUNTIME_DIRECTORY/brightness"

      [ -n "$RUNTIME_DIRECTORY" ] || exit 0
      [ -r "$led" ] || exit 0

      level="$(cat "$led")"
      case "$level" in
        '' | *[!0-9]*) exit 0 ;;
      esac

      printf '%s\n' "$level" > "$state"
    '';
    preStop = ''
      led=/sys/class/leds/tpacpi::kbd_backlight
      state="$RUNTIME_DIRECTORY/brightness"

      [ -n "$RUNTIME_DIRECTORY" ] || exit 0
      [ -r "$state" ] || exit 0
      [ -w "$led/brightness" ] || exit 0

      level="$(cat "$state")"
      case "$level" in
        '' | *[!0-9]*) exit 0 ;;
      esac

      max=0
      if [ -r "$led/max_brightness" ]; then
        max="$(cat "$led/max_brightness")"
      fi
      case "$max" in
        '' | *[!0-9]*) max=0 ;;
      esac
      if [ "$level" -gt "$max" ]; then
        exit 0
      fi

      printf '%s\n' "$level" > "$led/brightness"
    '';
  };
}
