{
  powerManagement.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # logind's compiled defaults, made explicit: undocked lid close suspends,
  # docked (docking station or >1 display connected) lid close is ignored by
  # logind. Hyprland (modules/home/hyprland.nix) owns the docked half by
  # disabling the internal panel instead.
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchDocked = "ignore";
  };
}
