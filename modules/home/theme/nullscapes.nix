# Single source of truth for the Nullscapes theme, ported from
# triplespike/Spike-dotfiles (MIT, home.nix at rev 3cf70b7d).
#
# `theme.nullscapes.dark`: the Nullscapes palette, the 16 Noctalia m*
# color roles plus a `terminal` section (ANSI 16 + fg/bg/cursor/
# selection), transcribed verbatim from the source's
# `programs.noctalia.customPalettes.Nullscapes.dark`. Same shape as
# theme/mactahoe.nix, so every consumer reads it the same way. Dark only.
#
# Nullscapes is terminal-only: the active desktop theme is MacTahoe
# (theme/mactahoe.nix). This module sets no GTK theme, icon theme or cursor.
#
# Consumers:
#   - modules/home/kitty.nix      (terminal palette)
#   - modules/home/fastfetch.nix  (noctalia fastfetch theme colors)
{ lib, ... }:
let
  dark = {
    mPrimary = "#678FE4";
    mOnPrimary = "#181C25";
    mSecondary = "#715CD6";
    mOnSecondary = "#EEF4FF";
    mTertiary = "#AB66CC";
    mOnTertiary = "#181B24";
    mError = "#FD4663";
    mOnError = "#181C25";
    mSurface = "#141B29";
    mOnSurface = "#F2F2F3";
    mSurfaceVariant = "#1B2437";
    mOnSurfaceVariant = "#AFB1B6";
    mOutline = "#616771";
    mShadow = "#141B29";
    mHover = "#283653";
    mOnHover = "#F2F2F3";
    terminal = {
      background = "#080B16";
      foreground = "#E8EDFF";
      cursor = "#A8B7FF";
      cursorText = "#090C18";
      selectionBg = "#344879";
      selectionFg = "#FFFFFF";
      normal = {
        black = "#080B16";
        red = "#E8758D";
        green = "#79B9B5";
        yellow = "#C8CBE6";
        blue = "#6480D7";
        magenta = "#8A91E8";
        cyan = "#82B8E8";
        white = "#E8EDFF";
      };
      bright = {
        black = "#46516F";
        red = "#FF91A5";
        green = "#A0D8CF";
        yellow = "#F1F3FF";
        blue = "#829AFF";
        magenta = "#B2BBFF";
        cyan = "#AED8FF";
        white = "#FFFFFF";
      };
    };
  };
in
{
  options.theme.nullscapes = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf (lib.types.oneOf [
      lib.types.str
      (lib.types.attrsOf (lib.types.oneOf [
        lib.types.str
        (lib.types.attrsOf lib.types.str)
      ]))
    ]));
    readOnly = true;
    description = ''
      Nullscapes palette from triplespike/Spike-dotfiles. Exposes a dark
      variant with the 16 Noctalia m* roles plus a `terminal` section (ANSI 16
      + fg/bg/cursor/selection). Read as `config.theme.nullscapes.dark.<key>`.
    '';
    default = { inherit dark; };
  };
}
