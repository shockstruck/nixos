# Switch off the ASUS Aura USB motherboard/fan-header RGB controller
# (idVendor=0b05, idProduct=19af) at boot and after every resume. A single
# oneshot CLI run, not services.hardware.openrgb: that module runs a
# persistent `openrgb --server` daemon (Restart=always) and loads
# i2c-dev/i2c-piix4 for SMBus probing, neither of which this needs — the
# controller enumerates over USB HID, not SMBus, and we want the LEDs off
# once, not a lighting server kept running. Verified against source before
# writing (nixpkgs e158d9ed9b51c98974c5e66e1ba1c9e0255fecaa, openrgb 1.0,
# github.com/CalcProgrammer1/OpenRGB @ release_1.0, the GitHub mirror of the
# Codeberg source nixpkgs' pkgs/by-name/op/openrgb/package.nix fetches from):
#   Controllers/AsusAuraUSBController/AsusAuraUSBControllerDetect.cpp:40,51,420
#     `#define AURA_USB_VID 0x0B05`, `#define AURA_MOTHERBOARD_3_PID 0x19AF`,
#     `REGISTER_HID_DETECTOR_PU("ASUS Aura Motherboard",
#     DetectAsusAuraUSBMotherboards, AURA_USB_VID, AURA_MOTHERBOARD_3_PID,
#     0xFF72, 0x00A1)` — 0b05:19af is detected as an ASUS Aura Motherboard
#     controller.
#   Controllers/AsusAuraUSBController/AsusAuraUSBController/
#     AsusAuraUSBController.h:21 `AURA_MODE_OFF = 0` and
#     RGBController_AsusAuraUSB.cpp:45-50 register a mode named literally
#     "Off" (`color_mode = MODE_COLORS_NONE`, no color needed) on the base
#     class RGBController_AuraUSB, which
#     RGBController_AsusAuraMainboard.cpp's RGBController_AuraMainboard
#     (used for the Motherboard detector above) extends without removing it
#     — so an "off" mode exists for this controller and static/000000 is not
#     needed.
#   cli.cpp:345-353 `ParseMode()`: `-m`/`--mode` is matched with
#     `strcasecmp()` against each mode's `GetModeName()`, so `--mode off`
#     selects the "Off" mode above; `-d`/`--device` is omitted here, which
#     cli.cpp's help text (line 423) documents as applying to all detected
#     devices.
#   cli.cpp:451 help text and cli.cpp:1450-1454 `else if(option ==
#     "--noautoconnect") { ret_flags |= RET_FLAG_NO_AUTO_CONNECT; ... }`;
#     startup/main_FreeBSD_Linux_MacOS.cpp:83-88 passes
#     `!(ret_flags & RET_FLAG_NO_AUTO_CONNECT)` as the autoconnect argument
#     to `ResourceManager::get()->Initialize(...)` — with `--noautoconnect`
#     given (and `--nodetect` not given), the CLI skips connecting to an
#     already-running SDK server and performs local hardware detection
#     itself, so no `services.hardware.openrgb` server needs to be running.
{ lib, pkgs, ... }:
let
  sleepTargets = [
    "suspend.target"
    "hibernate.target"
    "hybrid-sleep.target"
    "suspend-then-hibernate.target"
  ];
in
{
  systemd.services.rgb-off = {
    description = "Switch off the ASUS Aura chassis and fan LEDs";
    after = [ "systemd-udev-settle.service" ] ++ sleepTargets;
    wantedBy = [ "multi-user.target" ] ++ sleepTargets;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "-${lib.getExe' pkgs.openrgb "openrgb"} --noautoconnect --mode off";
      TimeoutStartSec = 30;
    };
  };
}
