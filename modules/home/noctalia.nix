# Noctalia V5 shell (noctalia-dev/noctalia-shell), replacing DankMaterialShell
# (SHOA-1004 / parent SHOA-997 C1 — DMS removed, no fallback per parent Q4).
#
# Noctalia is a single Quickshell/QML shell layer that owns the common desktop
# surfaces (bar, launcher, control center, notifications, OSD, wallpaper). It is
# started as a systemd user service bound to `config.wayland.systemd.target`
# (defaults to graphical-session.target). niri-flake's user services satisfy
# graphical-session.target, so niri launches Noctalia — no niri spawn-at-startup
# entry is required (this mirrors how DMS was started via systemd, not niri
# spawn, so the shell is not double-launched).
#
# Idle + locking stay delegated to stasis + swaylock (SHOA-1002, idle.nix):
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

      # systemd user service on graphical-session.target (niri-flake satisfies
      # it), so Noctalia autostarts under niri. `package` is defaulted by the
      # upstream homeModules.default to the flake's noctalia package.
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

        # Locking is owned by swaylock (driven by stasis; SHOA-1002). Disable
        # Noctalia's built-in lock screen so there is a single locker. Noctalia's
        # own idle behaviours default to disabled, so stasis remains the single
        # idle manager.
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
