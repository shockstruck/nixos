# Callpackaged the same way modules/home/packages.nix consumes
# ../../packages/paperweight.nix.
{ pkgs, ... }:
let
  opengameinstaller = pkgs.callPackage ../../../packages/opengameinstaller.nix { };
in
{
  environment.systemPackages = [
    pkgs.heroic
    pkgs.protonup-qt
    pkgs.mangohud
    opengameinstaller
  ];
}
