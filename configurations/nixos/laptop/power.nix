{
  powerManagement.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # logind's compiled defaults, made explicit: undocked lid close suspends,
  # docked (docking station or >1 display connected) lid close is ignored by
  # logind. niri owns the docked half by turning the internal panel off
  # while the lid is closed (modules/home/niri.nix).
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchDocked = "ignore";
  };
}
