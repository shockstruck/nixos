# CachyOS-inspired scheduling tweaks. Verified against nixpkgs source before
# writing:
#   nixos/modules/services/scheduling/scx.nix: enable, scheduler (an enum of
#     cfg.package.schedulers, which includes "scx_lavd").
#   nixos/modules/services/misc/ananicy.nix: enable, package, rulesProvider.
#   pkgs/top-level/linux-kernels.nix: `linux_default = packages.linux_6_18;` —
#     the flake takes boot.kernelPackages from this default (no override in
#     this repo), and 6.18 > 6.14, the version ntsync landed in upstream.
{ pkgs, ... }:

{
  # Proton-GE uses /dev/ntsync when present for its NT synchronization
  # primitive emulation. Landed upstream in 6.14; this flake's default kernel
  # (linux_6_18, see header) is well past that. Not verified: whether
  # nixpkgs' default (non-zen) kernel config builds CONFIG_NTSYNC — the only
  # explicit `NTSYNC = yes;` found in nixpkgs source is in
  # pkgs/os-specific/linux/kernel/zen-kernels.nix, which this host does not
  # use. If the module isn't built, this list entry is a harmless no-op
  # (systemd-modules-load logs and continues); flagged for Kevin to confirm
  # /dev/ntsync exists after activation.
  boot.kernelModules = [ "ntsync" ];
  services.udev.extraRules = ''
    KERNEL=="ntsync", MODE="0660", TAG+="uaccess"
  '';

  # No LACT on the console: Steam's Quick Access Performance controls own
  # the amdgpu sysfs knobs here through steamos-manager
  # (./steamos-manager.nix), and lactd re-applying its own profile to
  # power_dpm_force_performance_level / power1_cap would silently undo them.
  # The desktop keeps LACT (configurations/nixos/desktop/graphics.nix).

  # sched-ext; Valve's LAVD scheduler, tuned for gaming latency. Needs kernel
  # >= 6.12 — the flake's default linuxPackages on nixos-unstable satisfies
  # that already.
  services.scx = {
    enable = true;
    scheduler = "scx_lavd";
  };

  # CachyOS's ananicy-cpp + its community ruleset.
  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-rules-cachyos;
  };

  programs.gamemode.enable = true;

  # SteamOS/Fedora default for games that map many regions (mmap-heavy
  # engines, wine/proton).
  boot.kernel.sysctl."vm.max_map_count" = 2147483642;
}
