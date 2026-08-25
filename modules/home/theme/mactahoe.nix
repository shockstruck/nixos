# Single source of truth for the mactahoe-default palette (SHOA-1102).
#
# Vanilla mactahoe GTK theme defaults, transcribed verbatim from the pinned
# vinceliuice/MacTahoe-gtk-theme source (rev 2026-08-08, src/sass/_colors.scss
# + _colors-palette.scss, variant dark/light, scheme != nord, darker != true,
# default theme): dark/light variants, each with the 16 Noctalia m* color roles
# plus a `terminal` section (ANSI 16 + fg/bg/cursor/selection). No consumer
# module hardcodes a mactahoe hex — every consumer reads `config.theme.mactahoe`.
#
# Replaces the founder palette (SHOA-1094, theme/founder.nix).
#
# Consumers:
#   - modules/home/noctalia.nix   (default custom palette, dark mode)
#   - modules/home/kitty.nix      (dark terminal palette)
#   - modules/home/fastfetch.nix  (dark palette for the noctalia theme)
#   - modules/home/theme/mactahoe.nix (MacTahoe-Dark tint, dark variant)
#   - modules/home/hyprland.nix   (decoration background/border colors, dark)
{ lib, pkgs, config, ... }:
let
  dark = {
    mPrimary = "#0088FF";
    mOnPrimary = "#ffffff";
    mSecondary = "#2E7CF7";
    mOnSecondary = "#ffffff";
    mTertiary = "#9A57A3";
    mOnTertiary = "#ffffff";
    mError = "#ED5F5D";
    mOnError = "#ffffff";
    mSurface = "#242424";
    mOnSurface = "#dedede";
    mSurfaceVariant = "#333333";
    mOnSurfaceVariant = "#dadada";
    mOutline = "#999999";
    mShadow = "#000000";
    mHover = "#BFE1FF";
    mOnHover = "#242424";
    terminal = {
      normal = {
        black = "#242424";
        red = "#ED5F5D";
        green = "#79B757";
        yellow = "#F3BA4B";
        blue = "#2E7CF7";
        magenta = "#E55E9C";
        cyan = "#0088FF";
        white = "#dadada";
      };
      bright = {
        black = "#999999";
        red = "#ED5F5D";
        green = "#79B757";
        yellow = "#F3BA4B";
        blue = "#2E7CF7";
        magenta = "#E55E9C";
        cyan = "#0088FF";
        white = "#ffffff";
      };
      foreground = "#dadada";
      background = "#242424";
      cursor = "#dadada";
      cursorText = "#242424";
      selectionFg = "#ffffff";
      selectionBg = "#0088FF";
    };
  };
  light = {
    mPrimary = "#0088FF";
    mOnPrimary = "#ffffff";
    mSecondary = "#2E7CF7";
    mOnSecondary = "#ffffff";
    mTertiary = "#9A57A3";
    mOnTertiary = "#ffffff";
    mError = "#ED5F5D";
    mOnError = "#ffffff";
    mSurface = "#ffffff";
    mOnSurface = "#242424";
    mSurfaceVariant = "#f5f5f5";
    mOnSurfaceVariant = "#363636";
    mOutline = "#565656";
    mShadow = "#000000";
    mHover = "#BFE1FF";
    mOnHover = "#242424";
    terminal = {
      normal = {
        black = "#f5f5f5";
        red = "#ED5F5D";
        green = "#79B757";
        yellow = "#F3BA4B";
        blue = "#2E7CF7";
        magenta = "#E55E9C";
        cyan = "#0088FF";
        white = "#242424";
      };
      bright = {
        black = "#8C8C8C";
        red = "#ED5F5D";
        green = "#79B757";
        yellow = "#F3BA4B";
        blue = "#2E7CF7";
        magenta = "#E55E9C";
        cyan = "#0088FF";
        white = "#363636";
      };
      foreground = "#363636";
      background = "#ffffff";
      cursor = "#363636";
      cursorText = "#ffffff";
      selectionFg = "#ffffff";
      selectionBg = "#0088FF";
    };
  };
  # MacTahoe-Dark is tinted at build time from the mactahoe-default palette
  # (SHOA-1102, theme/mactahoe.nix): accent + dark surface colors are single
  # sass variables in the pinned vinceliuice source, so the compiled theme
  # carries the mactahoe default dark colors while the theme name stays
  # `MacTahoe-Dark` (only its compiled colors change).
  f = config.theme.mactahoe.dark;
  mactahoe = pkgs.callPackage ../../../packages/mactahoe-gtk-theme.nix {
    tint = {
      accent = f.mPrimary;
      onAccent = f.mOnPrimary;
      base = f.mSurface;
      bg = f.mSurfaceVariant;
      text = f.mOnSurface;
      fg = f.mOnSurfaceVariant;
    };
  };
in
{
  options.theme.mactahoe = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf (lib.types.oneOf [
      lib.types.str
      (lib.types.attrsOf (lib.types.oneOf [
        lib.types.str
        (lib.types.attrsOf lib.types.str)
      ]))
    ]));
    readOnly = true;
    description = ''
      Vanilla mactahoe GTK defaults palette (SHOA-1102), verbatim hexes from
      the pinned vinceliuice/MacTahoe-gtk-theme source. Replaces the founder
      palette (SHOA-1094). Exposes dark/light variants, each with the 16
      Noctalia m* roles plus a `terminal` section (ANSI 16 +
      fg/bg/cursor/selection). Read as
      `config.theme.mactahoe.dark.<key>` / `config.theme.mactahoe.light.<key>`.
    '';
    default = { inherit dark light; };
  };

  gtk = {
    enable = true;
    theme = {
      name = "MacTahoe-Dark";
      package = mactahoe;
    };
    gtk4.theme = config.gtk.theme;
  };
}
