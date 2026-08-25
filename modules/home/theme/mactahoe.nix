{ pkgs, config, ... }:
let
  # MacTahoe-Dark is tinted at build time from the founder palette (SHOA-1094,
  # theme/founder.nix): accent + dark surface colors are single sass variables
  # in the pinned vinceliuice source, so the compiled theme carries the founder
  # dark colors while the theme name stays `MacTahoe-Dark` (only its compiled
  # colors change).
  f = config.theme.founder.dark;
  mactahoe = pkgs.callPackage ../../../packages/mactahoe-gtk-theme.nix {
    tint = {
      accent = f.mPrimary;
      onAccent = f.mOnPrimary;
      base = f.mSurfaceVariant;
      bg = f.mSurface;
      text = f.mOnSurface;
      fg = f.mOnSurfaceVariant;
    };
  };
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
