# CachyOS-inspired scheduling tweaks. Verified against nixpkgs source before
# writing:
#   nixos/modules/services/scheduling/scx.nix: enable, scheduler (an enum of
#     cfg.package.schedulers, which includes "scx_lavd").
#   nixos/modules/services/misc/ananicy.nix: enable, package, rulesProvider.
{ pkgs, ... }:

{
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
