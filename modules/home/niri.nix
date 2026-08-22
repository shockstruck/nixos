{ config
, lib
, pkgs
, ...
}:
let
  # Run-or-raise helper (SHOA-1001). Packaged in ../../packages/niri-ror.nix
  # and also added to home.packages there (modules/home/packages.nix) so it's
  # on $PATH standalone; called by absolute store path here so the binds
  # below don't depend on PATH ordering.
  niri-ror = pkgs.callPackage ../../packages/niri-ror.nix { };

  # Guarded swaylock launcher (SHOA-1002). stasis no longer runs a locker in
  # response to `loginctl lock-session` (it only tracks logind LockedHint), so
  # the manual lock bind spawns swaylock directly. Identical to the guard in
  # modules/home/idle.nix, so both converge on a single swaylock instance.
  lockScript = pkgs.writeShellScript "swaylock-guarded" ''
    ${pkgs.procps}/bin/pidof swaylock >/dev/null 2>&1 || exec ${config.programs.swaylock.package}/bin/swaylock
  '';
in
{
  # The niri-flake Home Manager settings/actions API (`programs.niri.settings`,
  # `config.lib.niri.actions`) is injected into this home configuration by the
  # niri-flake NixOS module (`home-manager.sharedModules`, wired in
  # modules/nixos/gui/niri.nix), so this module does NOT import
  # `homeModules.niri` — doing so would re-declare `programs.niri.package` and
  # fail evaluation. niri itself is enabled and installed at the system layer;
  # here we only author the compositor settings. Its config.kdl writer
  # activates automatically once `settings` are set. DankMaterialShell's niri
  # home module (imported in dank-material-shell.nix) layers its matugen theme
  # includes on top of these settings.
  config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    home.pointerCursor = {
      enable = true;
      package = pkgs.adwaita-icon-theme;
      name = "Adwaita";
      size = 24;
    };

    programs.niri = {
      # Colors, layout, cursor, outputs, window-rules, alt-tab and wallpaper
      # blur are owned by DankMaterialShell's matugen includes
      # (`dms/*.kdl`, wired in dank-material-shell.nix). This module owns
      # input, keybinds, and session-global behaviour only. DMS's own bind
      # include is intentionally disabled there so the binds below are the
      # single source of truth (niri rejects duplicate binds).
      settings = {
        prefer-no-csd = true;
        hotkey-overlay.skip-at-startup = true;

        input = {
          keyboard.numlock = true;
          touchpad = {
            tap = true;
            natural-scroll = true;
          };
        };

        # XWayland via xwayland-satellite (see modules/nixos/gui/niri.nix).
        # Vicinae's launcher CLI (`vicinae toggle`, bound below) talks to this
        # daemon over IPC, so the server has to be running before the bind is
        # used; nixpkgs ships a systemd user unit for it but wiring that up
        # is out of scope here, so it's started the same way as
        # xwayland-satellite instead (mirrors extra/vicinae.service's
        # `vicinae server --replace` ExecStart upstream).
        spawn-at-startup = [
          { command = [ "xwayland-satellite" ]; }
          { command = [ "vicinae" "server" "--replace" ]; }
        ];

        binds = with config.lib.niri.actions; {
          # --- Applications & session ---
          "Mod+Return" = {
            action = spawn "kitty";
            hotkey-overlay.title = "Applications: Open terminal";
          };
          "Mod+Q" = {
            action = close-window;
            hotkey-overlay.title = "Windows: Close active window";
          };
          "Mod+L" = {
            # swaylock directly (guarded) — stasis does not lock on
            # `loginctl lock-session`, only tracks LockedHint (SHOA-1002).
            action = spawn "${lockScript}";
            hotkey-overlay.title = "Session: Lock screen";
          };
          # Vicinae launcher (SHOA-1000). Mod+Space is already DMS's
          # spotlight toggle, so Vicinae gets its own mnemonic bind; the
          # `vicinae server --replace` daemon is started via
          # spawn-at-startup above.
          "Mod+V" = {
            action = spawn "vicinae" "toggle";
            hotkey-overlay.title = "Applications: Toggle Vicinae launcher";
          };

          # --- Run-or-raise (niri-ror; SHOA-1001) ---
          # Focuses the app's existing window (cycling through matches) if
          # one is already open, otherwise launches it. See
          # https://github.com/boomskats/niri-ror for the matching rules.
          "Mod+T" = {
            action = spawn (lib.getExe niri-ror) "--app-id" "kitty" "--app-name" "Terminal" "--command" "kitty";
            hotkey-overlay.title = "Applications: Run-or-raise terminal";
          };
          "Mod+B" = {
            action = spawn (lib.getExe niri-ror) "--app-id" "brave-browser" "--app-name" "Browser" "--command" "brave";
            hotkey-overlay.title = "Applications: Run-or-raise browser";
          };

          # --- Column / window focus (scrollable-tiling) ---
          "Mod+Left".action = focus-column-left;
          "Mod+Right".action = focus-column-right;
          "Mod+Up".action = focus-window-up;
          "Mod+Down".action = focus-window-down;
          # Vim focus (H/J/K only; L is reserved for lock-session above).
          "Mod+H".action = focus-column-left;
          "Mod+J".action = focus-window-down;
          "Mod+K".action = focus-window-up;

          # --- Move column / window ---
          "Mod+Shift+Left".action = move-column-left;
          "Mod+Shift+Right".action = move-column-right;
          "Mod+Shift+Up".action = move-window-up;
          "Mod+Shift+Down".action = move-window-down;
          "Mod+Shift+H".action = move-column-left;
          "Mod+Shift+J".action = move-window-down;
          "Mod+Shift+K".action = move-window-up;

          # --- Workspaces 1–9 (focus / move column to) ---
          "Mod+1".action = focus-workspace 1;
          "Mod+2".action = focus-workspace 2;
          "Mod+3".action = focus-workspace 3;
          "Mod+4".action = focus-workspace 4;
          "Mod+5".action = focus-workspace 5;
          "Mod+6".action = focus-workspace 6;
          "Mod+7".action = focus-workspace 7;
          "Mod+8".action = focus-workspace 8;
          "Mod+9".action = focus-workspace 9;
          # niri-flake's typed actions (config.lib.niri.actions, generated
          # from niri's binds.rs) expose only the relative
          # move-column-to-workspace-{down,up}; the indexed variant is
          # dispatched through the niri CLI instead so Mod+Shift+N parity
          # with the previous Hyprland keymap is preserved.
          "Mod+Shift+1".action = spawn "niri" "msg" "action" "move-column-to-workspace" "1";
          "Mod+Shift+2".action = spawn "niri" "msg" "action" "move-column-to-workspace" "2";
          "Mod+Shift+3".action = spawn "niri" "msg" "action" "move-column-to-workspace" "3";
          "Mod+Shift+4".action = spawn "niri" "msg" "action" "move-column-to-workspace" "4";
          "Mod+Shift+5".action = spawn "niri" "msg" "action" "move-column-to-workspace" "5";
          "Mod+Shift+6".action = spawn "niri" "msg" "action" "move-column-to-workspace" "6";
          "Mod+Shift+7".action = spawn "niri" "msg" "action" "move-column-to-workspace" "7";
          "Mod+Shift+8".action = spawn "niri" "msg" "action" "move-column-to-workspace" "8";
          "Mod+Shift+9".action = spawn "niri" "msg" "action" "move-column-to-workspace" "9";

          # --- Column composition / sizing ---
          "Mod+BracketLeft".action = consume-or-expel-window-left;
          "Mod+BracketRight".action = consume-or-expel-window-right;
          "Mod+Comma".action = consume-window-into-column;
          "Mod+Period".action = expel-window-from-column;
          "Mod+R".action = switch-preset-column-width;
          "Mod+F".action = maximize-column;
          "Mod+Shift+F".action = fullscreen-window;
          "Mod+Minus".action = set-column-width "-10%";
          "Mod+Equal".action = set-column-width "+10%";

          # --- Native scroll-wheel column navigation ---
          # Replaces the Hyprland-only hypr-autoscroll plugin (dropped in the
          # compositor swap); niri has first-class scroll-wheel focus/move.
          "Mod+WheelScrollDown".action = focus-column-right;
          "Mod+WheelScrollUp".action = focus-column-left;
          "Mod+Shift+WheelScrollDown".action = move-column-right;
          "Mod+Shift+WheelScrollUp".action = move-column-left;

          # --- DankMaterialShell IPC (shell/bar/launcher) ---
          "Mod+Space" = {
            action = spawn "dms" "ipc" "call" "spotlight" "toggle";
            hotkey-overlay.title = "Shell: Toggle application launcher";
          };
          "Mod+S" = {
            action = spawn "dms" "ipc" "call" "settings" "toggle";
            hotkey-overlay.title = "Shell: Toggle settings";
          };
          "Mod+C" = {
            action = spawn "dms" "ipc" "call" "clipboard" "toggle";
            hotkey-overlay.title = "Shell: Toggle clipboard history";
          };
          "Mod+W" = {
            action = spawn "dms" "ipc" "call" "dankdash" "wallpaper";
            hotkey-overlay.title = "Shell: Choose wallpaper";
          };
          "Mod+Shift+E" = {
            action = spawn "dms" "ipc" "call" "powermenu" "toggle";
            hotkey-overlay.title = "Shell: Toggle power menu";
          };
          "Mod+A" = {
            action = spawn "dms" "ipc" "call" "widget" "toggle" "sathiAi";
            hotkey-overlay.title = "Shell: Toggle AI chat";
          };
          "Mod+N" = {
            action = spawn "dms" "ipc" "call" "control-center" "toggle";
            hotkey-overlay.title = "Shell: Toggle control center";
          };
          "Mod+M" = {
            action = spawn "dms" "ipc" "call" "dash" "toggle" "media";
            hotkey-overlay.title = "Shell: Toggle media dashboard";
          };
          "Mod+P" = {
            action = spawn "dms" "ipc" "call" "processlist" "toggle";
            hotkey-overlay.title = "Shell: Toggle process list";
          };
          "Mod+D" = {
            action = spawn "dms" "ipc" "call" "settings" "open";
            hotkey-overlay.title = "Utilities: Configure displays";
          };
          # Native niri overview replaces the Hyprland `dms ipc call hypr
          # toggleOverview` shim; the cheatsheet uses niri's hotkey overlay
          # in place of `dms ipc call hypr toggleBinds`.
          "Mod+Tab" = {
            action = toggle-overview;
            hotkey-overlay.title = "Shell: Toggle workspace overview";
          };
          "Mod+Slash" = {
            action = show-hotkey-overlay;
            hotkey-overlay.title = "Shell: Show keybind cheatsheet";
          };

          # --- Media / brightness keys (usable while locked) ---
          "XF86AudioRaiseVolume" = {
            allow-when-locked = true;
            action = spawn "dms" "ipc" "call" "audio" "increment" "5";
          };
          "XF86AudioLowerVolume" = {
            allow-when-locked = true;
            action = spawn "dms" "ipc" "call" "audio" "decrement" "5";
          };
          "XF86AudioMute" = {
            allow-when-locked = true;
            action = spawn "dms" "ipc" "call" "audio" "mute";
          };
          "XF86AudioMicMute" = {
            allow-when-locked = true;
            action = spawn "dms" "ipc" "call" "audio" "micmute";
          };
          "XF86MonBrightnessUp" = {
            allow-when-locked = true;
            action = spawn "dms" "ipc" "call" "brightness" "increment" "5";
          };
          "XF86MonBrightnessDown" = {
            allow-when-locked = true;
            action = spawn "dms" "ipc" "call" "brightness" "decrement" "5";
          };
          "XF86AudioPlay" = {
            allow-when-locked = true;
            action = spawn "dms" "ipc" "call" "mpris" "playPause";
          };
          "XF86AudioNext" = {
            allow-when-locked = true;
            action = spawn "dms" "ipc" "call" "mpris" "next";
          };
          "XF86AudioPrev" = {
            allow-when-locked = true;
            action = spawn "dms" "ipc" "call" "mpris" "previous";
          };

          # --- Exit niri ---
          "Ctrl+Alt+Delete".action = quit;
        };
      };
    };
  };
}
