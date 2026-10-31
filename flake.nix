{
  description = "ShockStruck's shared NixOS workstation configuration";

  inputs = {
    # Principle inputs (updated by `nix run .#update`)
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nixos-hardware.inputs.nixpkgs.follows = "nixpkgs";
    nixos-unified.url = "github:srid/nixos-unified";

    # Compositor: Hyprland is the Wayland compositor (SHOA-1037, reverting the
    # compositor swap SHOA-997). It is enabled at the system layer via the built-in
    # nixpkgs `programs.hyprland` module (modules/nixos/gui/hyprland.nix) and
    # configured for Home Manager via the built-in `wayland.windowManager.hyprland`
    # module (modules/home/hyprland.nix) — neither needs a dedicated flake input.

    # stasis: the idle manager, consumed by modules/home/idle.nix via its Home
    # Manager module (`flake.inputs.stasis.homeModules.default`).
    stasis.url = "github:saltnpepper97/stasis/v1.7.0";
    stasis.inputs.nixpkgs.follows = "nixpkgs";
    stasis.inputs.flake-parts.follows = "flake-parts";

    # Software inputs
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    nixvim.url = "github:nix-community/nixvim";
    nixvim.inputs.nixpkgs.follows = "nixpkgs";
    nixvim.inputs.flake-parts.follows = "flake-parts";
    # Noctalia V5 shell (Quickshell/QML) — a single configurable Wayland shell
    # layer (bar, launcher, control center, notifications, lock, OSD, wallpaper)
    # replacing DankMaterialShell (SHOA-1004 / parent SHOA-997 C1). Its
    # `homeModules.default` provides the `programs.noctalia` Home-Manager
    # interface consumed by modules/home/noctalia.nix; the systemd user service
    # binds to graphical-session.target, which the Hyprland session satisfies.
    noctalia.url = "github:noctalia-dev/noctalia-shell/v5.4.1";
    noctalia.inputs.nixpkgs.follows = "nixpkgs";

    # CachyOS kernel for the console (modules/nixos/console/kernel.nix). The
    # `release` branch only carries kernels its Hydra has already cached. No
    # `nixpkgs.follows`: upstream forbids it (patches and kernel version can
    # mismatch) and it would lose the binary cache.
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    nix-cachyos-kernel.inputs.flake-parts.follows = "flake-parts";
  };

  # Wired using https://nixos-unified.org/guide/autowiring
  outputs = inputs:
    inputs.nixos-unified.lib.mkFlake {
      inherit inputs;
      root = ./.;
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
    };
}
