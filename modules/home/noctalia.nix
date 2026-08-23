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
# Idle + locking stay delegated to hypridle + swaylock (SHOA-993/1037,
# hypridle.nix):
# Noctalia's own lock screen is disabled so the two idle managers do not fight
# (the previous DMS module made the same handoff via its zeroed idle timeouts).
#
# Theming consumes the standard Eldritch palette module from C7
# (SHOA-999, theme/eldritch.nix): the exact eldritchtheme/eldritch base16 values
# are exported verbatim as a Noctalia custom palette
# (~/.config/noctalia/palettes/eldritch.json) and selected as the active theme
# via `theme.source = "custom"`. See
# https://docs.noctalia.dev/noctalia/theming/palette/ for the palette JSON schema
# and https://docs.noctalia.dev/noctalia/configuration/ for the config reference.
{ config
, flake
, lib
, pkgs
, ...
}:
let
  # Single source of truth for the palette (SHOA-999 theme/eldritch.nix).
  p = config.theme.eldritch;
in
{
  imports = [ flake.inputs.noctalia.homeModules.default ];

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
        };

        # Active theme = the standard Eldritch palette from C7, exported below as
        # a custom palette. Dark mode only (the palette provides a dark variant).
        theme = {
          mode = "dark";
          source = "custom";
          custom_palette = "eldritch";
        };

        # Locking is owned by swaylock (driven by hypridle; SHOA-993/1037).
        # Disable Noctalia's built-in lock screen so there is a single locker.
        # Noctalia's own idle behaviours default to disabled, so hypridle remains
        # the single idle manager.
        lockscreen.enabled = false;

        # Weather parity with the previous DMS session (Detroit, °F).
        weather = {
          enabled = true;
          unit = "fahrenheit";
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
        wallpaper.automation.enabled = true;

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
      };

      # Standard Eldritch palette (eldritchtheme/eldritch base16) mapped onto
      # Noctalia's 16 color roles, consumed from the C7 module. Written to
      # ~/.config/noctalia/palettes/eldritch.json and selected by
      # `theme.custom_palette = "eldritch"` above. Dark variant only; Noctalia
      # reuses it for light mode when `light` is omitted.
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
