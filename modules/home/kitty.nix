{ pkgs, config, ... }:
let
  # Eldritch palette source of truth (modules/home/theme/eldritch.nix).
  e = config.theme.eldritch;
in
{
  # Ported from mooniri (revaljonathan/mooniri) config/kitty/kitty.conf. The
  # colors are driven by the shared Eldritch palette (SHOA-997 C7) rather than
  # the original static Tokyo Night Moon set. matugen/petalslinger
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
      cursor = e.base05;
      tab_title_template = "{title}";

      cursor_trail = 10;
      cursor_trail_decay = "0.1 0.9";
      cursor_trail_start_threshold = 0;

      # Eldritch theme (modules/home/theme/eldritch.nix).
      background = e.base00;
      foreground = e.base05;
      selection_background = e.base02;
      selection_foreground = e.base00;
      url_color = e.base0C;
      cursor_text_color = e.base00;

      active_tab_background = e.base0D;
      active_tab_foreground = e.base00;
      inactive_tab_background = e.base01;
      inactive_tab_foreground = e.base04;

      active_border_color = e.base0D;
      inactive_border_color = e.base01;

      # Standard base16 ANSI mapping.
      color0 = e.base00;
      color1 = e.base08;
      color2 = e.base0B;
      color3 = e.base0A;
      color4 = e.base0D;
      color5 = e.base0E;
      color6 = e.base0C;
      color7 = e.base05;

      color8 = e.base03;
      color9 = e.base08;
      color10 = e.base0B;
      color11 = e.base0A;
      color12 = e.base0D;
      color13 = e.base0E;
      color14 = e.base0C;
      color15 = e.base07;
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
