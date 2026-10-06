# Single source of truth for the Nullscapes theme, ported from
# triplespike/Spike-dotfiles (MIT, home.nix at rev 3cf70b7d).
#
# Two halves:
#   - `theme.nullscapes.dark`: the Nullscapes palette, the 16 Noctalia m*
#     color roles plus a `terminal` section (ANSI 16 + fg/bg/cursor/
#     selection), transcribed verbatim from the source's
#     `programs.noctalia.customPalettes.Nullscapes.dark`. Same shape as
#     theme/mactahoe.nix, so every consumer reads it the same way. Dark only;
#     Noctalia reuses the dark variant for light mode when `light` is absent.
#   - the application theme: GTK theme, icon theme, cursor and GTK font, as the
#     source sets them in `gtk` and `home.pointerCursor`.
#
# Consumers:
#   - modules/home/noctalia.nix   (active custom palette)
#   - modules/home/niri.nix       (focus ring, tab indicator, shadow, overview)
#   - modules/home/kitty.nix      (terminal palette)
#   - modules/home/fastfetch.nix  (noctalia fastfetch theme colors)
#
# Not ported from the source's GTK block: `gtk-modules =
# "colorreload-gtk-module"` (the module is not installed here) and the
# `ocean` sound theme (no sound theme package is installed here either).
{ lib, pkgs, config, ... }:
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

  config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    home.pointerCursor = {
      enable = true;
      gtk.enable = true;
      x11.enable = true;
      package = pkgs.catppuccin-cursors.mochaDark;
      name = "catppuccin-mocha-dark-cursors";
      size = 20;
    };

    gtk = {
      enable = true;
      font = {
        name = "Noto Sans";
        size = 10;
        package = pkgs.noto-fonts;
      };
      theme = {
        name = "adw-gtk3-dark";
        package = pkgs.adw-gtk3;
      };
      iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.catppuccin-papirus-folders.override {
          flavor = "mocha";
          accent = "lavender";
        };
      };
      gtk4.theme = config.gtk.theme;
      # Drives gtk-application-prefer-dark-theme in gtk-3.0/gtk-4.0 settings.ini
      # and the GSettings/portal color-scheme, via home-manager's gtk3/gtk4 modules.
      colorScheme = "dark";
      gtk3.extraConfig = {
        gtk-decoration-layout = "icon:minimize,maximize,close";
        gtk-enable-animations = true;
        gtk-primary-button-warps-slider = true;
      };
      gtk4.extraConfig = {
        gtk-decoration-layout = "icon:minimize,maximize,close";
        gtk-enable-animations = true;
        gtk-primary-button-warps-slider = true;
      };
    };
  };
}
