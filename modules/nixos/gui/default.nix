{
  imports = [
    ./hyprland.nix
  ];

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

  services.xserver.enable = true;
}
