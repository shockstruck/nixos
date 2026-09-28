# Switch off the ASUS Aura USB motherboard/fan-header RGB controller
# (0b05:19af) at boot and after every resume. The console already runs the
# OpenRGB server (services.hardware.openrgb, imported by path from
# configurations/nixos/desktop/hardware.nix), so this is a client of that
# server, never a second instance probing HID or SMBus devices itself.
# Verified against source before writing (nixpkgs e158d9e: openrgb 1.0 from
# Codeberg tag release_1.0, read at the GitHub mirror
# CalcProgrammer1/OpenRGB tag release_1.0):
#   Controllers/AsusAuraUSBController/AsusAuraUSBControllerDetect.cpp:
#     AURA_MOTHERBOARD_3_PID 0x19AF is registered as "ASUS Aura Motherboard",
#     and DetectAsusAuraUSBMotherboards names the controller
#     "ASUS " + DMIInfo::getMainboard(); dmiinfo/dmiinfo.cpp reads that from
#     the DMI board_name. RGBController_AsusAuraUSB.cpp registers an "Off"
#     mode (AURA_MODE_OFF) that the mainboard controller inherits.
#   startup/main_FreeBSD_Linux_MacOS.cpp passes !RET_FLAG_NO_DETECT as
#     Initialize()'s detectDevices; ResourceManager.cpp Initialize() connects
#     to the local server first and, when that succeeds, runs in client mode
#     with detection disabled. With --nodetect a failed connection leaves an
#     empty device list instead of falling back to local detection.
#   ResourceManager.cpp UpdateDeviceList() merges the client's controllers
#     into the list the CLI resolves --device against.
#   cli.cpp OptionDevice(): --device "name" is a case-insensitive substring
#     match on the controller name; no match prints "Cannot find device" and
#     cli_post_detection() exits -1. That is the retry signal below: at boot
#     the server may not be listening or may not have detected the
#     controller yet. --device keeps the mode off every other controller:
#     ParseMode() falls back to mode 0 on a device without an "Off" mode
#     rather than skipping it.
#   cli.cpp --config: must be an existing directory. Without it, a root
#     unit with no HOME writes OpenRGB.json into its working directory.
# Resume: the kernel resets the controller in place on every resume (same
# USB device number, no re-enumeration), so the server keeps its handle.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.hardware.openrgb;

  sleepTargets = [
    "suspend.target"
    "hibernate.target"
    "hybrid-sleep.target"
    "suspend-then-hibernate.target"
  ];

  # DMI board_name of the console's mainboard, from the kernel's
  # "DMI: ASUS System Product Name/TUF GAMING B850M-PLUS WIFI" line.
  auraDevice = "TUF GAMING B850M-PLUS WIFI";

  rgbOff = pkgs.writeShellApplication {
    name = "rgb-off";
    runtimeInputs = [ cfg.package pkgs.coreutils ];
    text = ''
      for _ in {1..30}; do
        if openrgb --config "$STATE_DIRECTORY" --nodetect --device ${lib.escapeShellArg auraDevice} --mode off; then
          exit 0
        fi
        sleep 2
      done
      exit 1
    '';
  };
in
{
  assertions = [
    {
      assertion = cfg.enable && cfg.server.port == 6742;
      message = "modules/nixos/console/rgb.nix drives the Aura controller through the local OpenRGB server on its default port 6742.";
    }
  ];

  systemd.services.rgb-off = {
    description = "Switch off the ASUS Aura chassis and fan LEDs";
    wants = [ "openrgb.service" ];
    after = [ "openrgb.service" ] ++ sleepTargets;
    wantedBy = [ "multi-user.target" ] ++ sleepTargets;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe rgbOff;
      StateDirectory = "rgb-off";
      TimeoutStartSec = 120;
    };
  };
}
