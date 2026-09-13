# Callpackaged the same way modules/home/packages.nix consumes
# ../../packages/paperweight.nix.
# lutris (pkgs/by-name/lu/lutris/package.nix) and umu-launcher
# (pkgs/by-name/um/umu-launcher/package.nix) confirmed present in nixpkgs
# source at the pinned rev.
{ pkgs, ... }:
let
  opengameinstaller = pkgs.callPackage ../../../packages/opengameinstaller.nix { };
in
{
  environment.systemPackages = [
    pkgs.heroic
    pkgs.protonup-qt
    pkgs.mangohud
    pkgs.lutris
    pkgs.umu-launcher
    opengameinstaller
  ];
}
