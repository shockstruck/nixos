{ pkgs, config, ... }:
let
  # Founder palette dark terminal colors, source of truth
  # (modules/home/theme/founder.nix, SHOA-1094).
  f = config.theme.founder.dark;
in
{
  # Ported from mooniri (revaljonathan/mooniri) config/kitty/kitty.conf. The
  # colors are driven by the founder palette (SHOA-1094, theme/founder.nix)
  # rather than the original static Tokyo Night Moon set. matugen/petalslinger
  # dynamic-theming includes are intentionally not ported.
  home.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

  programs.kitty = {
    enable = true;

    font = {
      name = "JetBrainsMono Nerd Font";
      size = 13;
    };

    settings = {
      shell_integration = "no-cursor";
      remember_window_size = "no";
      scrollback_lines = 2000;
      wheel_scroll_min_lines = 1;
      enable_audio_bell = "no";
      hide_window_decorations = "yes";
      background_opacity = "0.95";
      dynamic_background_opacity = "no";
      confirm_os_window_close = 0;
      cursor_shape = "underline";
      cursor_blink_interval = "1.0";
      cursor_stop_blinking_after = 30;
      repaint_delay = 8;
      input_delay = 0;
      window_padding_width = 8;
      cursor = f.terminal.cursor;
      tab_title_template = "{title}";

      cursor_trail = 10;
      cursor_trail_decay = "0.1 0.9";
      cursor_trail_start_threshold = 0;

      # Founder palette dark terminal colors (modules/home/theme/founder.nix).
      background = f.terminal.background;
      foreground = f.terminal.foreground;
      selection_background = f.terminal.selectionBg;
      selection_foreground = f.terminal.selectionFg;
      url_color = f.mTertiary;
      cursor_text_color = f.terminal.cursorText;

      active_tab_background = f.mPrimary;
      active_tab_foreground = f.mOnPrimary;
      inactive_tab_background = f.mSurfaceVariant;
      inactive_tab_foreground = f.mOnSurfaceVariant;

      active_border_color = f.mPrimary;
      inactive_border_color = f.mOutline;

      # Standard ANSI mapping onto the founder terminal palette.
      color0 = f.terminal.normal.black;
      color1 = f.terminal.normal.red;
      color2 = f.terminal.normal.green;
      color3 = f.terminal.normal.yellow;
      color4 = f.terminal.normal.blue;
      color5 = f.terminal.normal.magenta;
      color6 = f.terminal.normal.cyan;
      color7 = f.terminal.normal.white;

      color8 = f.terminal.bright.black;
      color9 = f.terminal.bright.red;
      color10 = f.terminal.bright.green;
      color11 = f.terminal.bright.yellow;
      color12 = f.terminal.bright.blue;
      color13 = f.terminal.bright.magenta;
      color14 = f.terminal.bright.cyan;
      color15 = f.terminal.bright.white;
    };

    keybindings = {
      "ctrl+shift+left" = "neighboring_window left";
      "ctrl+shift+right" = "neighboring_window right";
      "ctrl+shift+up" = "neighboring_window up";
      "ctrl+shift+down" = "neighboring_window down";
      "ctrl+tab" = "next_tab";
      "ctrl+grave" = "previous_tab";

      # Font-size zoom + page scroll bindings, ported from
      # s1devist1/my-linux-hp config/kitty/kitty.conf (SHOA-1058). Only the
      # keybindings are ported; the source theme/transparency/font/`shell fish`
      # are not (the curated founder-palette baseline above stays).
      "ctrl+plus" = "change_font_size all +1";
      "ctrl+equal" = "change_font_size all +1";
      "ctrl+kp_add" = "change_font_size all +1";
      "ctrl+minus" = "change_font_size all -1";
      "ctrl+underscore" = "change_font_size all -1";
      "ctrl+kp_subtract" = "change_font_size all -1";
      "ctrl+0" = "change_font_size all 0";
      "ctrl+kp_0" = "change_font_size all 0";
      "page_up" = "scroll_page_up";
      "page_down" = "scroll_page_down";
    };
  };
}
