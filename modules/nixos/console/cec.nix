# HDMI-CEC one-touch-play and TV standby for the Pulse-Eight USB-CEC
# adapter. Console-only: the GPU goes straight into the TV's HDMI 2.1 input
# (untouched video path, 4K120 + VRR intact); the adapter's own HDMI lead
# goes into a spare TV input; USB to the console. Verified against source
# before writing:
#   nixpkgs pkgs/by-name/li/libcec/package.nix: libcec 8.1.7, cmakeFlags
#     include -DHAVE_LINUX_API=1; ships cec-client.
#   Pulse-Eight/libcec src/cec-client/cec-client.cpp: -s executes exactly
#     one stdin line then exits and "does not power on devices on startup
#     and power them off on exit"; -d {level} log level; -o {name} OSD
#     name; -p {port} / -b {logical addr} HDMI port and base device;
#     commands `on <addr>`, `standby <addr>`, `as` (in -s mode `as` waits
#     up to 15s for the TV to confirm).
#   Pulse-Eight/libcec src/libcec/CECClient.cpp SetPhysicalAddress(): the
#     physical address comes from explicit config, then autodetect, then
#     base+port. Autodetect on Linux is CUSBCECAdapterCommunication::
#     GetPhysicalAddress -> CDRMEdidParser, i.e. read from the GPU's own
#     connected-display EDID under /sys/class/drm, not from the adapter's
#     HDMI port (HAVE_DRM_EDID_PARSER is on for Linux in src/libcec/cmake/
#     CheckPlatformSupport.cmake). That is why wiring the adapter into a
#     spare port still targets the right input: the TV's EDID on the GPU's
#     port carries that port's physical address. -p/-b below are only the
#     fallback used when the EDID read yields 0 (TV unplugged/EDID
#     unavailable).
#   Pulse-Eight/libcec src/libcec/adapter/Pulse-Eight/
#     USBCECAdapterDetection.cpp: adapter is USB 2548:1001 / 2548:1002, a
#     cdc_acm device (/dev/ttyACM*), autodetected by libcec via libudev; no
#     port argument needed.
#   ublue-os/bazzite system_files/desktop/shared/usr/lib/systemd/system/
#     cec-onboot.service, cec-onsleep.service, cec-onpoweroff.service: the
#     unit shapes below are theirs.
#   dlundqvist/xone v0.5.8 transport/dongle.c: the driver calls
#     device_wakeup_enable() and sets needs_remote_wakeup once firmware is
#     ready, so the xone dongle is already armed as a wakeup source with no
#     config change needed here; only the CEC adapter's own USB remote
#     wakeup is disabled below, so idle CEC traffic from the TV cannot
#     resume the console.
{ pkgs, ... }:
let
  # TV input the GPU is plugged into (an HDMI 2.1 port on the Hisense U8H).
  # Only consulted when libcec cannot read the physical address from the
  # GPU's EDID; Kevin confirms the number from the TV's rear-panel label.
  hdmiPort = 3;

  cecClient = "${pkgs.libcec}/bin/cec-client -s -d 1 -o Console -b 0 -p ${toString hdmiPort}";
  cecCommand =
    name: command:
    pkgs.writeShellScript "cec-${name}" ''
      echo "${command}" | ${cecClient}
    '';
  sleepTargets = [
    "suspend.target"
    "hibernate.target"
    "hybrid-sleep.target"
    "suspend-then-hibernate.target"
  ];
in
{
  environment.systemPackages = [ pkgs.libcec ];

  services.udev.extraRules = ''
    # Pulse-Eight USB-CEC adapter: one-touch-play as soon as it enumerates (boot
    # and hotplug), and no USB remote wakeup from it — the controller is the
    # only wake path; idle CEC traffic from the TV must not resume the console.
    ACTION=="add", SUBSYSTEM=="tty", ATTRS{idVendor}=="2548", ATTRS{idProduct}=="1001|1002", TAG+="systemd", ENV{SYSTEMD_WANTS}+="cec-onboot.service"
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="2548", ATTR{idProduct}=="1001|1002", ATTR{power/wakeup}="disabled"
  '';

  systemd.services = {
    cec-onboot = {
      description = "HDMI-CEC: power on the TV and become the active source";
      after = sleepTargets;
      wantedBy = sleepTargets; # resume; boot/hotplug come from the udev rule
      serviceConfig = {
        Type = "oneshot";
        ExecStart = [
          "-${cecCommand "tv-on" "on 0"}"
          "-${cecCommand "active-source" "as"}"
        ];
        TimeoutStartSec = 60;
      };
    };
    cec-onsleep = {
      description = "HDMI-CEC: put the TV on standby before suspend";
      unitConfig.DefaultDependencies = false;
      before = [
        "systemd-suspend.service"
        "systemd-hibernate.service"
        "systemd-hybrid-sleep.service"
        "systemd-suspend-then-hibernate.service"
        "sleep.target"
      ];
      wantedBy = sleepTargets;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "-${cecCommand "tv-standby" "standby 0"}";
        TimeoutStartSec = 30;
      };
    };
    cec-onpoweroff = {
      description = "HDMI-CEC: put the TV on standby at poweroff";
      unitConfig.DefaultDependencies = false;
      before = [
        "systemd-poweroff.service"
        "poweroff.target"
      ];
      wantedBy = [ "poweroff.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "-${cecCommand "tv-standby" "standby 0"}";
        TimeoutStartSec = 30;
      };
    };
  };
}
