{
  boot.kernelParams = [ "amd_pstate=active" ];

  # amd-pstate-epp is a .setpolicy driver, so it never registers with the
  # generic cpufreq governor framework — schedutil (or any cpuFreqGovernor
  # value) cannot attach. The kernel lands on the powersave policy with EPP
  # balance_performance, and CPPC governs frequency autonomously from there.
  # Do not add powerManagement.cpuFreqGovernor here.
}
