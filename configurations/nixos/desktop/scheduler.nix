# sched-ext userspace scheduler (SHOC-84). Desktop only: this lives under
# configurations/nixos/desktop/ rather than modules/, because modules/ reaches
# both hosts and the laptop is a ThinkPad P15s Gen 2 that runs on battery.
{
  services.scx = {
    enable = true;
    scheduler = "scx_lavd";

    # No extraArgs on purpose. scx_lavd enables its autopilot when no power
    # flag is given, and autopilot picks powersave/balanced/performance from
    # measured capacity each tick. `--performance` requires autopilot to be
    # off, so it replaces adaptive selection with permanently unparked cores
    # (no_core_compaction) — autopilot reaches performance mode under
    # sustained load anyway. Add it later only if measurement justifies it.
    #
    # Caveat: power.nix sets amd_pstate=active (the amd-pstate-epp driver,
    # where the hardware manages P-states) alongside cpuFreqGovernor =
    # "schedutil". scx_lavd does its own frequency scaling through cpufreq,
    # so those hints may have nowhere to land. It does not stop scx_lavd from
    # scheduling; settling it means reading scaling_driver and
    # scaling_available_governors under /sys on the running desktop.
  };
}
