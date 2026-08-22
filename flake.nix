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

    # niri: scrollable-tiling Wayland compositor. niri-flake provides the
    # typed `programs.niri.settings` API and `config.lib.niri.actions` bind
    # DSL that DankMaterialShell's first-class niri home module targets
    # (nixpkgs' `programs.niri` has no Home-Manager settings interface).
    niri-flake.url = "github:sodiboo/niri-flake";
    niri-flake.inputs.nixpkgs.follows = "nixpkgs";

    # stasis: Rust Wayland idle manager. Replaces swayidle as the single idle
    # manager (SHOA-1002); its Home Manager module provides `services.stasis`,
    # wired in modules/home/idle.nix.
    stasis.url = "github:saltnpepper97/stasis/v1.5.1";
    stasis.inputs.nixpkgs.follows = "nixpkgs";
    stasis.inputs.flake-parts.follows = "flake-parts";

    # Software inputs
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    nixvim.url = "github:nix-community/nixvim";
    nixvim.inputs.nixpkgs.follows = "nixpkgs";
    nixvim.inputs.flake-parts.follows = "flake-parts";
    dank-material-shell.url = "github:AvengeMedia/DankMaterialShell/v1.5.3";
    dank-material-shell.inputs.nixpkgs.follows = "nixpkgs";
    dms-plugin-registry.url = "github:AvengeMedia/dms-plugin-registry";
    dms-plugin-registry.inputs.nixpkgs.follows = "nixpkgs";
  };

  # Wired using https://nixos-unified.org/guide/autowiring
  outputs = inputs:
    inputs.nixos-unified.lib.mkFlake {
      inherit inputs;
      root = ./.;
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
    };
}
