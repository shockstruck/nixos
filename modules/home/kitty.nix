{ pkgs, ... }:
{
  # Ported from mooniri (revaljonathan/mooniri) config/kitty/kitty.conf +
  # config/kitty/current-theme.conf (Tokyo Night Moon). Static theme only —
  # matugen/petalslinger dynamic-theming includes are intentionally not
  # ported.
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
      cursor = "#ffb8c4";
      tab_title_template = "{title}";

      cursor_trail = 10;
      cursor_trail_decay = "0.1 0.9";
      cursor_trail_start_threshold = 0;

      # Tokyo Night Moon theme (config/kitty/current-theme.conf)
      background = "#222436";
      foreground = "#c8d3f5";
      selection_background = "#ffb8c4";
      selection_foreground = "#1e2030";
      url_color = "#4fd6be";
      cursor_text_color = "#222436";

      active_tab_background = "#82aaff";
      active_tab_foreground = "#1e2030";
      inactive_tab_background = "#2f334d";
      inactive_tab_foreground = "#545c7e";

      active_border_color = "#82aaff";
      inactive_border_color = "#2f334d";

      color0 = "#1b1d2b";
      color1 = "#ff757f";
      color2 = "#c3e88d";
      color3 = "#ffc777";
      color4 = "#82aaff";
      color5 = "#c099ff";
      color6 = "#86e1fc";
      color7 = "#828bb8";

      color8 = "#444a73";
      color9 = "#ff8d94";
      color10 = "#c7fb6d";
      color11 = "#ffd8ab";
      color12 = "#9ab8ff";
      color13 = "#fca7ea";
      color14 = "#b2ebff";
      color15 = "#c8d3f5";

      color16 = "#ff966c";
      color17 = "#c53b53";
      color18 = "#fca7ea";
    };

    keybindings = {
      "ctrl+shift+left" = "neighboring_window left";
      "ctrl+shift+right" = "neighboring_window right";
      "ctrl+shift+up" = "neighboring_window up";
      "ctrl+shift+down" = "neighboring_window down";
      "ctrl+tab" = "next_tab";
      "ctrl+grave" = "previous_tab";
    };
  };
}
