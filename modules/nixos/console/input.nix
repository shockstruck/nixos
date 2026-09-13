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

  # Bluetooth Xbox controllers.
  hardware.xpadneo.enable = true;

  # Broader controller support (PlayStation, generic pads) via udev rules
  # from fabiscafe/game-devices-udev.
  services.udev.packages = [ pkgs.game-devices-udev-rules ];
  hardware.uinput.enable = true;
}
