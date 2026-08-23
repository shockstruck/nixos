{ pkgs, config, ... }:
let
  mactahoe = pkgs.callPackage ../../../packages/mactahoe-gtk-theme.nix { };
in
{
  gtk = {
    enable = true;
    theme = {
      name = "MacTahoe-Dark";
      package = mactahoe;
    };
    gtk4.theme = config.gtk.theme;
  };
}
