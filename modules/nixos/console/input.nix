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
  # Keep the dongle on a CPU-attached USB port (xHCI 0000:0e:00.3 or
  # 0000:0e:00.4). On the chipset controller (0000:0b:00.0) xone v0.5.8
  # fails every cold boot, reboot and resume (control message failed: -121,
  # load firmware failed: -19, init radio failed: -108) and only a physical
  # replug recovers it (dlundqvist/xone#183); a USB de-/re-authorize does
  # not.
  hardware.xone.enable = true;

  # Bluetooth Xbox controllers.
  hardware.xpadneo.enable = true;

  # Broader controller support (PlayStation, generic pads) via udev rules
  # from fabiscafe/game-devices-udev.
  services.udev.packages = [ pkgs.game-devices-udev-rules ];
  hardware.uinput.enable = true;
}
