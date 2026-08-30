# Noctalia V5 shell (noctalia-dev/noctalia-shell), replacing DankMaterialShell
# (SHOA-1004 / parent SHOA-997 C1 — DMS removed, no fallback per parent Q4).
#
# Noctalia is a single Quickshell/QML shell layer that owns the common desktop
# surfaces (bar, launcher, control center, notifications, OSD, wallpaper). It is
# started as a systemd user service bound to `config.wayland.systemd.target`
# (defaults to graphical-session.target). The Hyprland session
# (`wayland.windowManager.hyprland.systemd.enable`, modules/home/hyprland.nix)
# satisfies graphical-session.target, so Hyprland launches Noctalia — no
# compositor exec-once entry is required (this mirrors how DMS was started via
# systemd, so the shell is not double-launched).
#
# Idle is delegated to stasis (SHOA-1040, modules/home/idle.nix), which runs
# Noctalia's shell-native lock screen via `noctalia msg session lock`; its own
# idle behaviours default off, so the two idle managers do not fight (the
# previous DMS module made the same handoff via its zeroed idle timeouts).
#
# Theming consumes the mactahoe-default palette module (SHOA-1102,
# theme/mactahoe.nix) as the single source of truth: the exact mactahoe default
# hexes are exported verbatim as a Noctalia custom palette
# (~/.config/noctalia/palettes/mactahoe.json) and selected as the active theme
# via `theme.source = "custom"` / `theme.custom_palette = "mactahoe"`. The
# standard Eldritch palette (SHOA-999, theme/eldritch.nix) remains available as
# a custom palette but is no longer the default. See
# https://docs.noctalia.dev/noctalia/theming/palette/ for the
# palette JSON schema and https://docs.noctalia.dev/noctalia/configuration/ for
# the config reference.
{ config
, flake
, lib
, pkgs
, ...
}:
let
  # Single source of truth for the mactahoe-default palette (SHOA-1102
  # theme/mactahoe.nix). `f.dark` / `f.light` carry the exact 16 m* keys +
  # terminal shape Noctalia's palette schema expects (same shape as the working
  # eldritch palette).
  f = config.theme.mactahoe;

  # Standard Eldritch palette (SHOA-999 theme/eldritch.nix), kept available as a
  # custom palette — no longer the active default.
  p = config.theme.eldritch;

  # Wallpaper collection ported from s1devist1/my-linux-hp (SHOA-1058).
  wallpapers = pkgs.callPackage ../../packages/wallpapers.nix { };
in
{
  imports = [ flake.inputs.noctalia.homeModules.default ];

  # home-manager gained its own `programs.noctalia` module upstream
  # (modules/programs/noctalia.nix, 2026-08-24), and home-manager auto-discovers
  # everything under modules/programs via readDir. Its option declarations
  # collide with the ones in the noctalia flake's homeModules.default, which
  # broke evaluation outright when the weekly lock bump pulled that
  # home-manager in (SHOC-46).
  #
  # Keep the flake's module and disable home-manager's copy: the flake is pinned
  # to v5.0.0-beta.9, defaults `package` to the flake's own build, and provides
  # the `settings` / `validateConfig` interface configured below, none of which
  # home-manager's module offers. The path is spelled absolutely because
  # home-manager does not set `modulesPath`, so a relative entry would not
  # resolve.
  disabledModules = [
    "${flake.inputs.home-manager}/modules/programs/noctalia.nix"
  ];

  config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    programs.noctalia = {
      enable = true;

      # systemd user service on graphical-session.target (the Hyprland session
      # satisfies it), so Noctalia autostarts under Hyprland. `package` is
      # defaulted by the upstream homeModules.default to the flake's noctalia
      # package.
      systemd.enable = true;

      # Validate config.toml against the shell's schema at build time; a schema
      # error fails the Nix build (the workstation's CI eval/build gate).
      validateConfig = true;

      # config.toml (TOML). Only workstation-specific overrides are set; every
      # other key keeps Noctalia's documented default (see example.toml upstream).
      settings = {
        shell = {
          font_family = "Google Sans Flex";
          time_format = "{:%I:%M %p}"; # 12-hour clock (DMS clockFormat = "12h")
          date_format = "%a, %m/%d"; # DMS clockDateFormat = "ddd, MM/dd"

          # my-linux-hp port (SHOA-1058) — shell additions; niri_overview_*
          # and app_icon_color intentionally not ported (Hyprland session,
          # not niri; source icon color kept default).
          corner_radius_scale = 1.5;
          password_style = "random";
          polkit_agent = true;
          screen_time_enabled = true;
          launcher.app_grid = true;
          panel = {
            transparency_mode = "glass";
            session_placement = "floating";
            session_position = "center";
            open_near_click_control_center = true;
          };
          screen_corners.enabled = true;
        };

        # Active theme = the mactahoe-default palette (SHOA-1102,
        # theme/mactahoe.nix), exported below as a custom palette. Dark mode
        # (the palette provides dark + light variants; `mode = "dark"` selects
        # the dark one).
        theme = {
          mode = "dark";
          source = "custom";
          custom_palette = "mactahoe";
        };

        # Locking is Noctalia-native (SHOA-1040), driven by stasis
        # (modules/home/idle.nix) and the Hyprland SUPER+L bind: `noctalia msg
        # session lock` authenticates via the always-present `login` PAM service
        # and is idempotent while a lock is active. Noctalia's own idle
        # behaviours default to disabled, so stasis remains the single idle
        # manager.
        lockscreen.enabled = true;

        # Weather + measurement units (SHOA-1073). Noctalia's ONLY unit key is
        # `weather.unit`; it is compared literally against "imperial"
        # (WeatherService::useImperial, noctalia-shell v5.0.0-beta.9 / rev
        # a064c063). "imperial" drives Fahrenheit temperature, mph wind speed,
        # and feet elevation together; the default "metric" gives °C / km/h / m.
        # The prior "fahrenheit" value was a no-op (it != "imperial", so it
        # silently rendered °C). US/imperial units for Detroit.
        weather = {
          enabled = true;
          unit = "imperial";
        };
        location = {
          auto_locate = false;
          address = "Detroit, MI";
        };

        # ── DMS plugin/widget parity (SHOA-1008 / folds parent C10) ──────────
        #
        # The removed DMS module ran a set of plugins/widgets. Noctalia covers
        # the following DMS plugins with first-class builtins, so they need no
        # plugin port — only the settings/bar wiring below:
        #   - calculator     → launcher provider [shell.launcher.providers.
        #                       calculator], on by default (global search), so no
        #                       extra config is needed for parity.
        #   - clipboard      → the `clipboard` bar widget (below) + shell
        #                       clipboard, on by default (shell.clipboard_enabled).
        #   - wallpaperCarousel → [wallpaper.automation] (enabled below).
        #   - system monitor → [system.monitor] (enabled by default) surfaced by
        #                       the `sysmon` bar widget (cpu/mem instances below).
        #
        # DMS plugins with NO Noctalia builtin — sathiAi (Ollama chat),
        # claudeCodeUsage, dockerManager, dankKDEConnect (KDE Connect),
        # netbirdStatus (laptop), quickCapture — are intentionally DROPPED.
        # Removing DMS (SHOA-1004, 2890bc3) already dropped them; the founder
        # reviewed the accept-loss-vs-rebuild-as-Noctalia-plugin decision on
        # SHOA-1008 and accepted the loss for all six (rebuild none). They are
        # therefore not wired here and no plugin bar entries exist below. If any
        # are ever wanted back, that is a new founder-approved Quickshell/QML
        # plugin issue — not a change to this module's parity baseline.

        # wallpaperCarousel parity: rotate wallpapers from the wallpaper
        # directory. Interval/order keep Noctalia defaults (30 min, random).
        # my-linux-hp port (SHOA-1058) wallpaper keys; paths re-pointed at
        # the pa-wallpapers package store path.
        wallpaper = {
          automation.enabled = true; # wallpaperCarousel parity (see above)
          directory = "${wallpapers}/share/wallpapers";
          default.path = "${wallpapers}/share/wallpapers/MacTahoe-day.jpeg"; # placeholder choice — noted for founder
          edge_smoothness = 0.3;
          transition_duration = 2000;
          transition_on_startup = true;
        };

        # ── my-linux-hp port (SHOA-1058, source local/state/noctalia/
        #    settings.toml) ────────────────────────────────────────────────
        #
        # Ported from s1devist1/my-linux-hp local/state/noctalia/settings.toml
        # (SHOA-1058). Schema-verified against noctalia-shell v5.0.0-beta.9;
        # keys not valid in beta.9 were dropped (see child spec),
        # machine-specific paths (avatar, launcher image, absolute wallpaper
        # paths) are not ported, idle.* is intentionally NOT ported (stasis
        # owns idle per SHOA-1040), and the Nord theme/bar layout are NOT
        # ported (Eldritch + DMS-parity bar are the curated SHOA-999/1008
        # baseline).
        accessibility.ui_scale = 1.15;
        audio.enable_sounds = true;
        battery.warning_threshold = 15;
        brightness.minimum_brightness = 0.1;
        control_center = {
          sidebar_section = "full";
          width = 800;
          # 12-hour clock (SHOA-1028 sweep): calendar tab event times bypass
          # shell.time_format upstream (CalendarTab default "%H:%M", rev
          # a064c063) — this key is their only config surface.
          calendar.event_time_format = "%I:%M %p";
        };
        notification.background_opacity = 0.51;
        osd = {
          background_opacity = 0.3;
          scale = 1.2;
        };
        dock = {
          enabled = true;
          background_opacity = 0.0;
          border = "#5A5959";
          border_width = 1.0;
          cross_axis_padding = 0;
          item_spacing = 0;
          main_axis_padding = 8;
          margin_edge = 8;
          radius = 23;
          reserve_space = false;
          show_dots = true;
          smart_auto_hide = true;
          active_scale = 1.2;
          inactive_opacity = 1.0;
          launcher_position = "start";
          # Adapted to this repo's app set (source list was GNOME/Flatpak-specific).
          pinned = [ "firefox" "kitty" "obsidian" "org.telegram.desktop" "discord" "signal" ];
        };

        # Widget settings (all verified against beta.9 widget definitions).
        widget.active_window.display = "text_only";
        widget.battery.display_mode = "graphic";
        widget.network.show_label = false;
        widget.privacy.hide_inactive = true;
        widget.screenshot.enabled = false;
        widget.spacer_2 = {
          type = "spacer";
          length = 5;
        };
        widget.workspaces = {
          style = "focus_hint";
          active_pill_size = 2.5;
        };

        # Desktop widgets (ported from the source [desktop_widgets]; coords
        # are the source's — cx linearly scaled by 1920/2066.8 = 0.93 and
        # rounded, cy unchanged, targeting the eDP-1 1920x1080 laptop panel;
        # positions are runtime-adjustable in Noctalia's widget editor).
        # schema_version dropped (state bookkeeping), the "Read" button
        # dropped (machine-specific PDF path), "Game Mode" kept (needs
        # pkgs.fastfetch — modules/home/fastfetch.nix). Widget ids verbatim.
        desktop_widgets = {
          enabled = true;
          grid = {
            visible = true;
            cell_size = 16;
            major_interval = 4;
          };
          widget_order = [
            "desktop-widget-0000000000000002"
            "desktop-widget-0000000000000004"
            "desktop-widget-0000000000000005"
            "desktop-widget-0000000000000006"
            "desktop-widget-0000000000000007"
            "desktop-widget-0000000000000008"
            "desktop-widget-0000000000000009"
          ];
          widget = {
            "desktop-widget-0000000000000002" = {
              # sysmon: CPU
              type = "sysmon";
              output = "eDP-1";
              rotation = 0.0;
              box_height = 144.0;
              box_width = 224.0;
              cx = 1443.0;
              cy = 140.0;
              settings = {
                background_opacity = 0.5;
                background_radius = 25;
                stat = "cpu_usage";
                stat2 = "cpu_temp";
              };
            };
            "desktop-widget-0000000000000004" = {
              # sysmon: RAM
              type = "sysmon";
              output = "eDP-1";
              rotation = 0.0;
              box_height = 144.0;
              box_width = 224.0;
              cx = 1662.0;
              cy = 140.0;
              settings = {
                background_opacity = 0.5;
                background_radius = 25;
                stat = "ram_pct";
                stat2 = "swap_pct";
              };
            };
            "desktop-widget-0000000000000005" = {
              # media player
              type = "media_player";
              output = "eDP-1";
              rotation = 0.0;
              box_height = 176.0;
              box_width = 464.0;
              cx = 1550.0;
              cy = 316.0;
              settings = {
                background_color = "surface";
                background_opacity = 0.5;
                background_padding = 10;
                background_radius = 25;
              };
            };
            "desktop-widget-0000000000000006" = {
              # volume
              type = "volume";
              output = "eDP-1";
              rotation = 0.0;
              box_height = 144.0;
              box_width = 320.0;
              cx = 1483.0;
              cy = 492.0;
              settings = {
                background_opacity = 0.5;
                background_padding = 10;
                background_radius = 25;
                device = "output";
              };
            };
            "desktop-widget-0000000000000007" = {
              # calendar
              type = "calendar";
              output = "eDP-1";
              rotation = 0.0;
              box_height = 304.0;
              box_width = 320.0;
              cx = 1483.0;
              cy = 732.0;
              settings = {
                background_opacity = 0.5;
                background_radius = 25;
                font_family = "";
                show_events = false;
                show_week_numbers = false;
              };
            };
            "desktop-widget-0000000000000008" = {
              # audio visualizer
              type = "audio_visualizer";
              output = "eDP-1";
              rotation = 1.5707963705062866;
              box_height = 128.0;
              box_width = 464.0;
              cx = 1706.0;
              cy = 652.0;
              settings = {
                background = true;
                background_color = "surface";
                background_opacity = 0.5;
                background_padding = 10;
                background_radius = 25;
                bands = 16;
                centered = true;
                color_1 = "primary";
                color_2 = "hover";
                mirrored = true;
                show_when_idle = true;
              };
            };
            "desktop-widget-0000000000000009" = {
              # Game Mode button
              type = "button";
              output = "eDP-1";
              rotation = 0.0;
              box_height = 48.0;
              box_width = 144.0;
              cx = 1689.0;
              cy = 932.0;
              settings = {
                background = true;
                command = "kitty --hold fastfetch";
                glyph = "device-gamepad-3-filled";
                label = "Game Mode";
                variant = "primary";
              };
            };
          };
        };

        # Lockscreen widgets (ported from the source [lockscreen_widgets];
        # login_box + clock; ids verbatim).
        lockscreen_widgets = {
          enabled = true;
          widget_order = [ "lockscreen-login-box@eDP-1" "lockscreen-widget-0000000000000001" ];
          widget = {
            "lockscreen-login-box@eDP-1" = {
              type = "login_box";
              output = "eDP-1";
              rotation = 0.0;
              box_height = 196.0;
              box_width = 810.0;
              cx = 960.0;
              cy = 906.0;
              settings = {
                background_color = "surface_variant";
                background_opacity = 0.7;
                background_radius = 18.0;
                center_password_text = true;
                input_opacity = 1.0;
                input_radius = 16.0;
                layout = "regular";
                show_caps_lock = true;
                show_keyboard_layout = true;
                show_login_button = true;
                show_media = true;
                show_session_buttons = true;
                show_unlock_hint = true;
                show_weather = true;
              };
            };
            "lockscreen-widget-0000000000000001" = {
              type = "clock";
              output = "eDP-1";
              rotation = 0.0;
              box_height = 224.0;
              box_width = 304.0;
              cx = 960.0;
              cy = 380.0;
              settings = {
                background_opacity = 0.0;
                center_text = true;
                clock_style = "digital";
                color = "on_primary";
                # 12-hour format (SHOA-1095); DesktopWidgetFactory defaults
                # to "{:%H:%M}" (24h) when unset.
                format = "{:%I:%M %p}";
              };
            };
          };
        };

        # Bar parity with the DMS "Main Bar" (barConfigs.default). Widget ids are
        # the Noctalia v5.0.0-beta.9 builtin registry (src/shell/bar/
        # widget_factory.cpp). network/bluetooth/volume/brightness/session are
        # intentionally omitted from the bar — as in DMS they live in the
        # control-center panel, not the bar. The DMS plugin bar widgets
        # (sathiAi/dockerManager/claudeCodeUsage/netbirdStatus) are dropped per
        # the accepted SHOA-1008 decision, so they are absent from `end`.
        bar.main = {
          # DMS left: launcherButton, workspaceSwitcher, focusedWindow.
          start = [ "launcher" "workspaces" "active_window" ];
          # DMS center: music, clock, weather.
          center = [ "media" "clock" "weather" ];
          # DMS right (builtin-covered subset): systemTray, clipboard, cpuUsage,
          # memUsage, notificationButton, battery, controlCenterButton. The DMS
          # plugin widgets that sat here (sathiAi, dockerManager, claudeCodeUsage,
          # netbirdStatus) are dropped — see the parity note above.
          end = [
            "tray"
            "clipboard"
            "cpu" # sysmon (cpu_usage) — see [widget.cpu] below
            "mem" # sysmon (ram_pct)  — see [widget.mem] below
            "notifications"
            "battery" # builtin; auto-hides on machines without a battery
            "control-center"
          ];
        };

        # Two named `sysmon` instances give DMS cpuUsage/memUsage parity (the
        # single sysmon widget selects its metric via `stat`). Referenced by the
        # "cpu"/"mem" bar entries above.
        widget.cpu = {
          type = "sysmon";
          stat = "cpu_usage";
        };
        widget.mem = {
          type = "sysmon";
          stat = "ram_pct";
        };

        # Bar clock 12-hour format (SHOA-1095). The clock widget does not read
        # shell.time_format; its own `format` key (example.toml [widget.clock],
        # default "{:%H:%M}") is what renders the bar time.
        widget.clock = {
          format = "{:%I:%M %p}";
        };
      };

      # Mactahoe-default palette (SHOA-1102, theme/mactahoe.nix) mapped verbatim
      # onto Noctalia's 16 color roles + terminal section. Written to
      # ~/.config/noctalia/palettes/mactahoe.json and selected by
      # `theme.custom_palette = "mactahoe"` above. `validateConfig = true` is
      # unchanged: it validates config.toml (`theme.custom_palette` is a plain
      # string), and the generated palette JSON shape is identical to the
      # eldritch one already in production.
      customPalettes.mactahoe = {
        dark = f.dark;
        light = f.light;
      };

      # Standard Eldritch palette (eldritchtheme/eldritch base16) mapped onto
      # Noctalia's 16 color roles, consumed from the C7 module. Written to
      # ~/.config/noctalia/palettes/eldritch.json and still exported so the
      # palette remains selectable, but no longer the active default. Dark
      # variant only; Noctalia reuses it for light mode when `light` is omitted.
      customPalettes.eldritch.dark = {
        mPrimary = p.green; # #37f499 — eldritch signature accent
        mOnPrimary = p.background;
        mSecondary = p.blue; # #39ddfd
        mOnSecondary = p.background;
        mTertiary = p.purple; # #a48cf2
        mOnTertiary = p.background;
        mError = p.red; # #f16c75
        mOnError = p.background;
        mSurface = p.background; # #212337
        mOnSurface = p.foreground; # #ebfafa
        mSurfaceVariant = p.backgroundAlt; # #323449
        mOnSurfaceVariant = p.foregroundDim; # #a1abe0
        mOutline = p.comment; # #7081d0
        mShadow = p.background;
        mHover = p.selection; # #3b4261
        mOnHover = p.foreground;
        terminal = {
          background = p.background;
          foreground = p.foreground;
          cursor = p.foreground;
          cursorText = p.background;
          selectionBg = p.selection;
          selectionFg = p.foreground;
          normal = {
            black = p.selection;
            red = p.red;
            green = p.green;
            yellow = p.yellow;
            blue = p.blue;
            magenta = p.purple;
            cyan = p.cyan;
            white = p.foreground;
          };
          bright = {
            black = p.comment;
            red = p.red;
            green = p.green;
            yellow = p.orange;
            blue = p.blue;
            magenta = p.pink;
            cyan = p.cyan;
            white = p.white;
          };
        };
      };
    };
  };
}
