# Global `ujust` command (SHOC-46): a `just` wrapper pointed at a Nix-built
# justfile instead of one in $PWD, matching the shape of
# ublue-os/packages@main:packages/ublue-os-just/src/ujust. Auto-imported by
# ./default.nix's readDir, so this activates on both hosts with no import
# line anywhere.
{ pkgs, ... }:
let
  justfile = pkgs.writeText "ujust-justfile" ''
    # Global ujust recipes (SHOC-46). Run `ujust` from anywhere to list them.

    # Path to the nixos flake checkout the repo-scoped recipes below operate
    # on. Defaults to the current directory; export NIXOS_FLAKE to run them
    # from elsewhere.
    flake := env('NIXOS_FLAKE', '.')

    _default:
        #!${pkgs.bash}/bin/bash
        ${pkgs.just}/bin/just --list --list-heading $'Available commands:\n' --list-prefix $' - '

    # Update the flake inputs
    [group('repo')]
    update:
        nix flake update --flake {{flake}}

    # Lint nix files
    [group('repo')]
    lint:
        nix fmt {{flake}}

    # Check the nix flake
    [group('repo')]
    check:
        nix flake check {{flake}}

    # Manually enter the dev shell
    [group('repo')]
    dev:
        nix develop {{flake}}

    # Activate the configuration
    [group('repo')]
    run:
        nix run {{flake}}

    # Rebuild and switch to the new generation
    [group('repo')]
    switch:
        sudo nixos-rebuild switch --flake {{flake}}

    # Rebuild and set as the boot default without switching
    [group('repo')]
    boot:
        sudo nixos-rebuild boot --flake {{flake}}

    # Roll back to the previous generation
    [group('Main')]
    rollback:
        sudo nixos-rebuild switch --rollback

    # List system generations
    [group('Main')]
    generations:
        nix-env --list-generations --profile /nix/var/nix/profiles/system
  '';
in
{
  home.packages = [
    (pkgs.writeShellScriptBin "ujust" ''
      JUST_JUSTFILE="${justfile}" exec ${pkgs.just}/bin/just "$@"
    '')
  ];
}
