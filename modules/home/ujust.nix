# Global `ujust` command (SHOC-46): a `just` wrapper pointed at a Nix-built
# justfile instead of one in $PWD, matching the shape of
# ublue-os/packages@main:packages/ublue-os-just/src/ujust. Auto-imported by
# ./default.nix's readDir, so this activates on both hosts with no import
# line anywhere.
{ pkgs, ... }:
let
  justfile = pkgs.writeText "ujust-justfile" ''
    # Global ujust recipes (SHOC-46). Run `ujust` from anywhere to list them.

    _default:
        @just --list --list-heading $'Available commands:\n' --list-prefix $' - '

    # Update the flake inputs
    [group('Main')]
    update:
        nix flake update

    # Lint nix files
    [group('dev')]
    lint:
        nix fmt

    # Check the nix flake
    [group('dev')]
    check:
        nix flake check

    # Manually enter the dev shell
    [group('dev')]
    dev:
        nix develop

    # Activate the configuration
    [group('Main')]
    run:
        nix run

    # Rebuild and switch to the new generation
    [group('Main')]
    switch:
        sudo nixos-rebuild switch --flake .

    # Rebuild and set as the boot default without switching
    [group('Main')]
    boot:
        sudo nixos-rebuild boot --flake .

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
