# Expose this repo's own package definitions as flake outputs.
#
# Without this they are reachable only through `pkgs.callPackage` inside
# modules/home/packages.nix, so nothing outside that file can address them by
# name. That is why the update pipeline has never touched them: `nix flake
# update` only moves flake *inputs*, and these pin their own version and hash
# by hand. paperweight sat on 0.5.0 while upstream shipped 0.6.0.
#
# The "Update packaged apps" step in .github/workflows/update-flake-lock.yaml
# reaches them through these attributes, so a new file in packages/ is picked
# up by CI automatically once it is listed here.
#
# x86_64-linux only: these are AppImage wrappers and a GTK theme built with
# Linux-only tooling, and evaluating them for the darwin and aarch64 systems
# this flake also declares would serve no purpose.
{ lib, ... }:
{
  perSystem = { pkgs, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      packages = {
        mactahoe-gtk-theme = pkgs.callPackage ../../packages/mactahoe-gtk-theme.nix { };
        paperweight = pkgs.callPackage ../../packages/paperweight.nix { };
        splayer-next = pkgs.callPackage ../../packages/splayer-next.nix { };
        wallpapers = pkgs.callPackage ../../packages/wallpapers.nix { };
      };
    };
}
