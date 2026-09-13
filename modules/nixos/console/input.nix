# Both enabled because the pairing method (dongle vs. Bluetooth) is Kevin's
# choice at the TV. Verified against nixpkgs source before writing:
#   nixos/modules/hardware/xone.nix: hardware.xone.enable.
#   nixos/modules/hardware/xpadneo.nix: hardware.xpadneo.enable.
{
  # Xbox Wireless Adapter dongle; pulls the unfree xone-dongle-firmware
  # (allowUnfree is already set globally in modules/nixos/default.nix).
  hardware.xone.enable = true;

  # Bluetooth Xbox controllers.
  hardware.xpadneo.enable = true;
}
