# Single source of truth for the founder palette (SHOA-1094).
#
# Founder-provided palette, transcribed verbatim from the SHOA-1094 input:
# dark/light variants, each with the 16 Noctalia m* color roles plus a
# `terminal` section (ANSI 16 + fg/bg/cursor/selection). No consumer module
# hardcodes a founder hex — every consumer reads `config.theme.founder`.
#
# Consumers:
#   - modules/home/noctalia.nix   (default custom palette, dark mode)
#   - modules/home/kitty.nix      (dark terminal palette)
#   - modules/home/fastfetch.nix  (dark palette for the noctalia theme)
#   - modules/home/theme/mactahoe.nix (MacTahoe-Dark tint, dark variant)
#   - modules/home/hyprland.nix   (decoration background/border colors, dark)
{ lib, ... }:
let
  dark = {
    mPrimary = "#bfc7d9";
    mOnPrimary = "#29313f";
    mSecondary = "#c4c6ce";
    mOnSecondary = "#2e3037";
    mTertiary = "#cfc2d6";
    mOnTertiary = "#352d3d";
    mError = "#ffb4ab";
    mOnError = "#690005";
    mSurface = "#131314";
    mOnSurface = "#e4e2e3";
    mSurfaceVariant = "#1f1f21";
    mOnSurfaceVariant = "#c5c6cc";
    mOutline = "#45474c";
    mShadow = "#000000";
    mHover = "#cfc2d6";
    mOnHover = "#352d3d";
    terminal = {
      normal = {
        black = "#45474c";
        red = "#ffb4ab";
        green = "#bfc7d9";
        yellow = "#c4c6ce";
        blue = "#cfc2d6";
        magenta = "#bfc7d9";
        cyan = "#c4c6ce";
        white = "#e4e2e3";
      };
      bright = {
        black = "#8f9096";
        red = "#ffb4ab";
        green = "#bfc7d9";
        yellow = "#c4c6ce";
        blue = "#cfc2d6";
        magenta = "#bfc7d9";
        cyan = "#c4c6ce";
        white = "#e4e2e3";
      };
      foreground = "#e4e2e3";
      background = "#131314";
      cursor = "#e4e2e3";
      cursorText = "#131314";
      selectionFg = "#c5c6cc";
      selectionBg = "#45474c";
    };
  };
  light = {
    mPrimary = "#000000";
    mOnPrimary = "#ffffff";
    mSecondary = "#5c5e65";
    mOnSecondary = "#ffffff";
    mTertiary = "#000000";
    mOnTertiary = "#ffffff";
    mError = "#ba1a1a";
    mOnError = "#ffffff";
    mSurface = "#fcf8fa";
    mOnSurface = "#1b1b1d";
    mSurfaceVariant = "#f0edee";
    mOnSurfaceVariant = "#45474c";
    mOutline = "#c5c6cc";
    mShadow = "#000000";
    mHover = "#000000";
    mOnHover = "#ffffff";
    terminal = {
      normal = {
        black = "#e2e2e8";
        red = "#ba1a1a";
        green = "#000000";
        yellow = "#5c5e65";
        blue = "#000000";
        magenta = "#6c7384";
        cyan = "#71727a";
        white = "#1b1b1d";
      };
      bright = {
        black = "#75777c";
        red = "#ba1a1a";
        green = "#000000";
        yellow = "#5c5e65";
        blue = "#000000";
        magenta = "#6c7384";
        cyan = "#71727a";
        white = "#1b1b1d";
      };
      foreground = "#1b1b1d";
      background = "#fcf8fa";
      cursor = "#1b1b1d";
      cursorText = "#fcf8fa";
      selectionFg = "#45474c";
      selectionBg = "#e2e2e8";
    };
  };
in
{
  options.theme.founder = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf (lib.types.oneOf [
      lib.types.str
      (lib.types.attrsOf (lib.types.oneOf [
        lib.types.str
        (lib.types.attrsOf lib.types.str)
      ]))
    ]));
    readOnly = true;
    description = ''
      Founder-provided palette (SHOA-1094), verbatim hexes. Exposes
      dark/light variants, each with the 16 Noctalia m* roles plus a
      `terminal` section (ANSI 16 + fg/bg/cursor/selection). Read as
      `config.theme.founder.dark.<key>` / `config.theme.founder.light.<key>`.
    '';
    default = { inherit dark light; };
  };
}
