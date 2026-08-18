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
    hypr-autoscroll.url = "github:estebanhiram/hypr-autoscroll";
    hypr-autoscroll.flake = false;
  };

  # Wired using https://nixos-unified.org/guide/autowiring
  #
  # The nixos-unified autowire exposes `packages/<name>.nix` through
  # `pkgs.callPackage fn { }`, which cannot supply the flake-locked source.
  # Override the autowired `hypr-autoscroll` package so the standalone flake
  # output builds from the same pinned source as the Home Manager-loaded
  # plugin — a single source authority in `flake.lock`. `perSystem.packages`
  # is `lazyAttrsOf`, so the replaced autowire definition is never evaluated.
  outputs = inputs:
    let
      base = inputs.nixos-unified.lib.mkFlake {
        inherit inputs;
        root = ./.;
        systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      };
    in
    base // {
      packages = builtins.mapAttrs
        (system: sysPackages:
          sysPackages // {
            hypr-autoscroll = inputs.nixpkgs.legacyPackages.${system}.callPackage ./packages/hypr-autoscroll.nix {
              src = inputs.hypr-autoscroll;
            };
          })
        (base.packages or { });
    };
}
