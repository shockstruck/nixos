# A session profile, not hardware: imported only by the console host
# (configurations/nixos/console/default.nix), so it reaches neither desktop
# nor laptop. Hardware truth stays in modules/nixos/gui's counterpart,
# ../../../configurations/nixos/desktop/*, imported by path from the console
# host instead.
{
  imports = [
    ./session.nix
    ./performance.nix
    ./input.nix
    ./launchers.nix
    ./streaming.nix
  ];

  # Quiet boot / plymouth, copied from modules/nixos/gui/default.nix. No
  # services.xserver.enable here: gamescope does not need the X server stack
  # gui/default.nix enables for Hyprland.
  boot = {
    consoleLogLevel = 3;
    initrd.verbose = false;
    loader.timeout = 0;
    kernelParams = [
      "quiet"
      "udev.log_level=3"
      "rd.udev.log_level=3"
      "systemd.show_status=auto"
      "rd.systemd.show_status=auto"
    ];
    plymouth = {
      enable = true;
      theme = "bgrt";
    };
  };
}
