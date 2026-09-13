# Both enabled because the pairing method (dongle vs. Bluetooth) is Kevin's
# choice at the TV. Verified against nixpkgs source before writing:
#   nixos/modules/hardware/xone.nix: hardware.xone.enable.
#   nixos/modules/hardware/xpadneo.nix: hardware.xpadneo.enable.
#   nixos/modules/hardware/uinput.nix: hardware.uinput.enable.
#   pkgs/by-name/ga/game-devices-udev-rules/package.nix: longDescription says
#     it's meant for services.udev.packages (not systemPackages) and "you may
#     need to enable hardware.uinput". Its postInstall only installs
#     `src/*.rules` from fabiscafe/game-devices-udev (controller udev rules);
#     no ntsync rule in that set, so it doesn't collide with performance.nix's
#     ntsync udev rule.
{ pkgs, ... }:
{
  # Xbox Wireless Adapter dongle; pulls the unfree xone-dongle-firmware
  # (allowUnfree is already set globally in modules/nixos/default.nix).
  hardware.xone.enable = true;

  # Workaround for a driver regression: after a cold boot, xone's dongle
  # firmware/radio init fails (-71/-108) and only a physical replug
  # recovers it (dlundqvist/xone#188, #215; regressed between v0.5.5 and
  # v0.5.6, still unfixed as of the v0.5.8 this flake ships). #215 closed
  # on a udev-triggered de-authorize/re-authorize, which re-enumerates the
  # device exactly like a replug. Verified before writing:
  #   dlundqvist/xone tag v0.5.8, transport/dongle.c xone_dongle_id_table:
  #     the driver binds 045e:02e6, 045e:02fe, 045e:02f9, 045e:091e — match
  #     all four, same table the driver uses.
  #   torvalds/linux drivers/usb/core/hub.c: usb_deauthorize_device is
  #     usb_set_configuration(dev, -1); usb_authorize_device re-selects a
  #     configuration. Only the interfaces are re-registered — the
  #     usb_device itself gets no further "add" uevent — so a rule matching
  #     ACTION=="add" with ENV{DEVTYPE}=="usb_device" cannot re-fire on its
  #     own reauthorization. No loop.
  #   systemd/systemd man/systemd.device.xml: SYSTEMD_WANTS= is honoured
  #     only with TAG+="systemd", and only when the device first becomes
  #     active.
  # Remove once a fixed xone release lands in nixpkgs.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="045e", ATTR{idProduct}=="02e6|02fe|02f9|091e", TAG+="systemd", ENV{SYSTEMD_WANTS}+="xone-dongle-reauthorize@%k.service"
  '';

  systemd.services."xone-dongle-reauthorize@" =
    let
      script = pkgs.writeShellScript "xone-dongle-reauthorize" ''
        set -eu
        dev=/sys/bus/usb/devices/$1
        sleep 3
        [ -e "$dev/authorized" ] || exit 0
        echo 0 > "$dev/authorized"
        sleep 1
        echo 1 > "$dev/authorized"
      '';
    in
    {
      description = "Re-authorize Xbox Wireless Adapter %i after cold-boot radio init failure";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${script} %i";
      };
    };

  # Bluetooth Xbox controllers.
  hardware.xpadneo.enable = true;

  # Broader controller support (PlayStation, generic pads) via udev rules
  # from fabiscafe/game-devices-udev.
  services.udev.packages = [ pkgs.game-devices-udev-rules ];
  hardware.uinput.enable = true;
}
