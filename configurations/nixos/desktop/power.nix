{
  boot.kernelParams = [ "amd_pstate=active" ];

  # amd-pstate-epp is a .setpolicy driver, so it never registers with the
  # generic cpufreq governor framework — schedutil (or any cpuFreqGovernor
  # value) cannot attach. The kernel lands on the powersave policy with EPP
  # balance_performance, and CPPC governs frequency autonomously from there.
  # Do not add powerManagement.cpuFreqGovernor here.

  # power-profiles-daemon is the user-facing knob over that EPP hint
  # (balanced -> balance_performance, performance -> performance, power-saver
  # -> power), and Noctalia's control-center Power tab binds its
  # org.freedesktop.UPower.PowerProfiles bus plus UPower — without both
  # daemons the tab is empty. Same pair the laptop enables; the laptop's
  # powerManagement.enable (suspend hooks) stays laptop-only.
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
}
