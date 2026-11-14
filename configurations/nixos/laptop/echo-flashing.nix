# Flashing Echo devices from the laptop: firebreak, adb, a Chromium for the
# EchoMuse WebUSB/Web Serial wizard, and the USB access they need. Laptop only
# — nothing here touches modules/, so the desktop and console are unaffected.
{ config, lib, pkgs, ... }:
{
  environment.systemPackages = [
    (pkgs.callPackage ../../../packages/firebreak.nix { })
    pkgs.android-tools
    pkgs.chromium
  ];

  # firebreak refuses to run unless a plugdev group exists and the user is in
  # it. Group membership lives here, not in modules/nixos/common/myusers.nix,
  # for the same reason as libvirtd in the desktop virtualisation.nix.
  users.groups.plugdev = { };
  users.users = lib.genAttrs config.myusers (_: { extraGroups = [ "plugdev" ]; });

  # Shipped as a udev package, not services.udev.extraRules: extraRules is
  # 99-local.rules, which sorts after systemd's 73-seat-late.rules uaccess
  # step, so TAG+="uaccess" would never take effect. The first eight rules are
  # firebreak's README verbatim; the last two keep ModemManager off the
  # MediaTek serial ports.
  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "echo-flashing-udev-rules";
      destination = "/lib/udev/rules.d/51-echo-flashing.rules";
      text = ''
        SUBSYSTEM=="usb", ATTR{idVendor}=="1949", MODE="0660", GROUP="plugdev", TAG+="uaccess"
        SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", ATTR{idProduct}=="4ee2", MODE="0660", GROUP="plugdev", TAG+="uaccess"
        SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", ATTR{idProduct}=="d001", MODE="0660", GROUP="plugdev", TAG+="uaccess"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0bb4", ATTR{idProduct}=="0c01", MODE="0660", GROUP="plugdev", TAG+="uaccess"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0e8d", ATTR{idProduct}=="0003", MODE="0660", GROUP="plugdev", TAG+="uaccess"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0e8d", ATTR{idProduct}=="201c", MODE="0660", GROUP="plugdev", TAG+="uaccess"
        SUBSYSTEM=="tty", ATTRS{idVendor}=="0e8d", ATTRS{idProduct}=="0003", MODE="0660", GROUP="plugdev", TAG+="uaccess"
        SUBSYSTEM=="tty", ATTRS{idVendor}=="1949", ATTRS{idProduct}=="2007", MODE="0660", GROUP="plugdev", TAG+="uaccess"
        SUBSYSTEM=="tty", ATTRS{idVendor}=="0e8d", ATTRS{idProduct}=="0003", ENV{ID_MM_DEVICE_IGNORE}="1"
        SUBSYSTEM=="tty", ATTRS{idVendor}=="1949", ATTRS{idProduct}=="2007", ENV{ID_MM_DEVICE_IGNORE}="1"
      '';
    })
  ];
}
