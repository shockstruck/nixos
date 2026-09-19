# Steam's Quick Access "Performance" tab in gaming mode: GPU clock /
# performance level, GPU power profile, CPU governor and the sched-ext
# scheduler toggle. The client drives these through Valve's steamos-manager
# daemon (packages/steamos-manager.nix) over D-Bus; without the daemon the
# tab is empty on this host even though the session already starts Steam
# with the SteamOS flag set (./session.nix). Verified against upstream
# gitlab.steamos.cloud/holo/steamos-manager v26.4.1 (the tag the package
# pins; read on the evlaV/steamos-manager mirror) before writing:
#   README.md "Interface compatibility notes": the client probes each
#     interface/property on the bus at startup and hides what is missing —
#     a partial implementation is the supported case.
#   steamos-manager/src/bin/steamos-manager.rs: `--device-config <path>`
#     "Force the device config. This bypasses DMI matching, so use at your
#     own risk." Without it hardware.rs `DeviceConfig::load` walks
#     share/steamos-manager/devices/*.toml and matches `[[device]] dmi.*`
#     against /sys/class/dmi/id/{sys_vendor,board_name,product_name} by
#     exact string; the 26 upstream configs are handhelds, Decks and Valve's
#     Steam Machine, none of which is this board, and there is no generic
#     fallback — an unmatched machine gets no GPU interfaces at all. The
#     forced config below is how this desktop board gets one.
#   steamos-manager/src/hardware.rs: `DeviceConfig` is `#[serde(default)]`,
#     so a file carrying only the sections below parses; `device_variant()`
#     then reports "unknown", which only gates Deck extras (ambient light
#     sensor, Galileo Wi-Fi debug, Deck-only power-profile filtering).
#   steamos-manager/src/gpu.rs: `gpu_performance_level_driver()` and
#     `gpu_power_profile_driver()` need only `driver = "amdgpu"`; the
#     drivers read and write device/power_dpm_force_performance_level,
#     device/pp_power_profile_mode, device/pp_dpm_sclk and
#     device/pp_od_clk_voltage under the hwmon named `amdgpu`
#     (power.rs `find_hwmon` over /sys/class/hwmon) — generic amdgpu sysfs,
#     the same files LACT/CoreCtrl use, present on the RX 7900 XT.
#     pp_od_clk_voltage is only writable with the overdrive ppfeaturemask
#     bit, which ../../../configurations/nixos/desktop/hardware.nix
#     (`hardware.amdgpu.overdrive.enable`, imported by the console host)
#     already sets.
#   steamos-manager/src/power.rs: `TdpLimit1` (`[tdp_limit] method =
#     "amdgpu_hwmon"`, writes hwmon power1_cap) refuses to run without a
#     `[tdp_limit.range] min/max` and never reads the card's own
#     power1_cap_min/max, so those two numbers must come from the card
#     (see the TOML comment below); `CpuSchedulerManager` starts and stops
#     the systemd unit `scx.service` — the very unit ./performance.nix's
#     `services.scx` declares — and `CpuScaling1` writes cpufreq
#     scaling_governor; both need no configuration.
#   steamos-manager/src/manager/user.rs `create_interfaces`: an interface
#     is put on the session bus only once its driver instantiates, so a
#     section missing from the TOML means the client never sees that
#     control rather than seeing a broken one.
#   steamos-manager/src/daemon/user.rs `create_connections`: the user
#     daemon expects the root daemon on the system bus (it pings it, then
#     proceeds) and routes every sysfs write through it, hence two units.
#   data/system/com.steampowered.SteamOSManager1.conf (installed by the
#     package into services.dbus.packages): only root may own the system
#     bus name, any local user may call it — upstream's model, unchanged.
#   data/system/steamos-manager.service, data/user/steamos-manager.service:
#     the `Type`, `BusName`, restart and start-limit values copied below;
#     upstream binds the user unit to graphical-session.target, which the
#     Hyprland desktop session (./desktop.nix) reaches and the gamescope
#     session does not, so console-session (./session.nix) starts it
#     explicitly before steam-gamescope. The session bus D-Bus activation
#     file (SystemdService=steamos-manager.service) is installed too, so a
#     client call also starts it on demand.
#   Jovian-Experiments/Jovian-NixOS modules/steam/steam.nix: the same two
#     units wired through `systemd.packages` with the user unit wanted by
#     their gamescope-session.service — the shape mirrored here without
#     upstream's unit files, so `--device-config` needs no drop-in.
#
# Console-only by construction: this directory is imported by the console
# host alone, and the desktop keeps LACT (configurations/nixos/desktop/
# graphics.nix) for the same sysfs knobs. On the console LACT is retired in
# ./performance.nix: lactd re-applies its own profile to
# power_dpm_force_performance_level and power1_cap and would silently undo
# what Steam's sliders set.
{ pkgs, lib, ... }:
let
  steamos-manager = pkgs.callPackage ../../../packages/steamos-manager.nix { };

  # Forced device config (schema: hardware.rs `DeviceConfig`; examples:
  # upstream data/devices/steam-deck.toml, bc-250.toml). No `[[device]]`
  # entry: nothing here is DMI-matched. `[tdp_limit]` is deliberately absent
  # until the card's power1_cap_min/max/default are read on the console
  # (`cat /sys/class/drm/card*/device/hwmon/hwmon*/power1_cap{,_min,_max,_default}`,
  # microwatts); with them it is
  #   [tdp_limit]
  #   method = "amdgpu_hwmon"
  #   [tdp_limit.range]
  #   min = <W>
  #   max = <W>
  # and whether Steam's slider then scales to a desktop card's watts is an
  # on-console observation, not something upstream documents.
  deviceConfig = pkgs.writeText "steamos-manager-console.toml" ''
    [gpu_performance]
    driver = "amdgpu"

    [gpu_power_profile]
    driver = "amdgpu"
  '';

  daemon = "${lib.getExe' steamos-manager "steamos-manager"} --device-config ${deviceConfig}";

  # Upstream's unit values (data/{system,user}/steamos-manager.service).
  serviceConfig = {
    Type = "notify-reload";
    BusName = "com.steampowered.SteamOSManager1";
    Environment = "RUST_LOG=info";
    Restart = "on-failure";
    RestartSec = 1;
    RestartMaxDelaySec = 10;
    RestartSteps = 3;
  };
in
{
  # steamosctl on PATH for diagnosis (`steamosctl get-gpu-performance-level`
  # and friends talk to the user daemon over the session bus).
  environment.systemPackages = [ steamos-manager ];

  # System-bus policy + activation file and the session-bus activation file
  # from share/dbus-1/{system.d,system-services,services}.
  services.dbus.packages = [ steamos-manager ];

  systemd.services.steamos-manager = {
    description = "SteamOS Manager root daemon";
    wantedBy = [ "multi-user.target" ];
    startLimitIntervalSec = 120;
    startLimitBurst = 5;
    serviceConfig = serviceConfig // {
      ExecStart = "${daemon} -r";
    };
  };

  systemd.user.services.steamos-manager = {
    description = "SteamOS Manager user daemon";
    # Reached by the Hyprland desktop session; the gamescope session starts
    # this unit from console-session instead (header note).
    wantedBy = [ "graphical-session.target" ];
    startLimitIntervalSec = 120;
    startLimitBurst = 5;
    serviceConfig = serviceConfig // {
      ExecStart = daemon;
    };
  };
}
