# Single source of truth for the Eldritch palette.
#
# Palette decision (SHOA-997 Q1): standard `eldritchtheme/eldritch` applied
# broadly — no bespoke "Abyss" hex set. Hex values are the official base16
# scheme from tinted-theming/schemes (`base16/eldritch.yaml`, author
# https://github.com/eldritch-theme), a dark variant.
#
# Consumers read `config.theme.eldritch.<key>`. Both the canonical base16
# slots (base00..base0F) and readable semantic aliases are exposed; the
# aliases are derived from the base16 slots so there is exactly one set of
# hex values to keep aligned with upstream.
{ lib, ... }:
let
  # Canonical base16 Eldritch palette (tinted-theming/schemes base16/eldritch.yaml).
  base16 = {
    base00 = "#212337"; # default background
    base01 = "#323449"; # lighter background (status bars, line highlight)
    base02 = "#3b4261"; # selection background
    base03 = "#7081d0"; # comments, invisibles
    base04 = "#a1abe0"; # dark foreground (status bar text)
    base05 = "#ebfafa"; # default foreground
    base06 = "#f0f2f4"; # light foreground
    base07 = "#ffffff"; # lightest foreground
    base08 = "#f16c75"; # red — variables, errors
    base09 = "#f7c67f"; # orange — integers, constants
    base0A = "#f1fc79"; # yellow — classes, search highlight
    base0B = "#37f499"; # green — strings, additions
    base0C = "#04d1f9"; # cyan — support, regex, escapes
    base0D = "#39ddfd"; # blue — functions, headings
    base0E = "#a48cf2"; # purple — keywords
    base0F = "#f265b5"; # pink/magenta — deprecated, embeds
  };

  # Readable aliases derived strictly from the base16 slots above.
  semantic = {
    background = base16.base00;
    backgroundAlt = base16.base01;
    selection = base16.base02;
    comment = base16.base03;
    foregroundDim = base16.base04;
    foreground = base16.base05;
    foregroundBright = base16.base06;
    white = base16.base07;
    red = base16.base08;
    orange = base16.base09;
    yellow = base16.base0A;
    green = base16.base0B;
    cyan = base16.base0C;
    blue = base16.base0D;
    purple = base16.base0E;
    pink = base16.base0F;
  };
in
{
  options.theme.eldritch = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    readOnly = true;
    description = ''
      Standard Eldritch (eldritchtheme/eldritch) palette as hex strings.
      Exposes canonical base16 slots (base00..base0F) plus semantic aliases
      (background, foreground, red, green, …). Read as
      `config.theme.eldritch.<key>` from other Home Manager modules.
    '';
    default = base16 // semantic;
  };
}
