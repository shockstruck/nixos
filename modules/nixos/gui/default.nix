{
  imports = [
    ./hyprland.nix
  ];

  boot = {
    consoleLogLevel = 3;
    initrd.verbose = false;
    kernelParams = [
      "quiet"
      "udev.log_level=3"
      "rd.udev.log_level=3"
      "systemd.show_status=auto"
      "rd.systemd.show_status=auto"
    ];
    plymouth = {
      enable = true;
      theme = "breeze";
    };
  };

  services.xserver.enable = true;
}
