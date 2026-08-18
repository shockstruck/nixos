{ pkgs
, lib
, config
, flake
, ...
}:
let
  initialMonitorConfig = pkgs.writeText "hyprland-monitors.conf" ''
    monitor = , preferred, auto, 1
  '';

  # Build the plugin from the flake-locked source against the exact Hyprland
  # package Home Manager resolves for this configuration. ABI between the
  # plugin and compositor is unstable, so both must come from the same build.
  hypr-autoscroll = pkgs.callPackage ../../packages/hypr-autoscroll.nix {
    src = flake.inputs.hypr-autoscroll;
    hyprland = config.wayland.windowManager.hyprland.finalPackage;
  };
in
{
  config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    wayland.windowManager.hyprland = {
      enable = true;
      systemd.enable = true;
      configType = "hyprlang";

      # Declarative plugin load. Home Manager resolves this package at
      # `${package}/lib/lib${pname}.so`.
      plugins = [ hypr-autoscroll ];

      # nwg-displays owns this mutable file and reloads Hyprland after changes.
      extraConfig = ''
        source = ~/.config/hypr/monitors.conf
      '';

      settings = {
        input.touchpad.natural_scroll = true;

        "$mainMod" = "SUPER";

        # Plugin defaults to inactive; middle-button autoscroll starts only
        # after the SUPER+CTRL+A toggle.
        plugin.hypr_autoscroll.direct_activation = false;

        bindd = [
          "$mainMod, Return, Applications: Open terminal, exec, foot"
          "$mainMod, Q, Windows: Close active window, killactive"

          "$mainMod, left, Windows: Focus left, movefocus, l"
          "$mainMod, right, Windows: Focus right, movefocus, r"
          "$mainMod, up, Windows: Focus up, movefocus, u"
          "$mainMod, down, Windows: Focus down, movefocus, d"

          "$mainMod, 1, Workspaces: Switch to workspace 1, workspace, 1"
          "$mainMod, 2, Workspaces: Switch to workspace 2, workspace, 2"
          "$mainMod, 3, Workspaces: Switch to workspace 3, workspace, 3"
          "$mainMod, 4, Workspaces: Switch to workspace 4, workspace, 4"
          "$mainMod, 5, Workspaces: Switch to workspace 5, workspace, 5"

          "$mainMod SHIFT, 1, Workspaces: Move window to workspace 1, movetoworkspace, 1"
          "$mainMod SHIFT, 2, Workspaces: Move window to workspace 2, movetoworkspace, 2"
          "$mainMod SHIFT, 3, Workspaces: Move window to workspace 3, movetoworkspace, 3"
          "$mainMod SHIFT, 4, Workspaces: Move window to workspace 4, movetoworkspace, 4"
          "$mainMod SHIFT, 5, Workspaces: Move window to workspace 5, movetoworkspace, 5"

          # DankMaterialShell surfaces.
          "$mainMod, Space, Shell: Toggle application launcher, exec, dms ipc call spotlight toggle"
          "$mainMod, S, Shell: Toggle settings, exec, dms ipc call settings toggle"
          "$mainMod, C, Shell: Toggle clipboard history, exec, dms ipc call clipboard toggle"
          "$mainMod, W, Shell: Choose wallpaper, exec, dms ipc call dankdash wallpaper"
          "$mainMod SHIFT, E, Shell: Toggle power menu, exec, dms ipc call powermenu toggle"
          "$mainMod, A, Shell: Toggle AI chat, exec, dms ipc call widget toggle sathiAi"
          "$mainMod, N, Shell: Toggle control center, exec, dms ipc call control-center toggle"
          "$mainMod, M, Shell: Toggle media dashboard, exec, dms ipc call dash toggle media"
          "$mainMod, P, Shell: Toggle process list, exec, dms ipc call processlist toggle"
          "$mainMod, Tab, Shell: Toggle workspace overview, exec, dms ipc call hypr toggleOverview"
          "$mainMod, slash, Shell: Toggle keybind cheatsheet, exec, dms ipc call hypr toggleBinds"

          "$mainMod, D, Utilities: Configure displays, exec, nwg-displays"

          # Keep SUPER+A for AI chat and move middle-button autoscroll.
          "$mainMod CTRL, A, Utilities: Toggle middle-button autoscroll, hypr-autoscroll:middle-mode, toggle"
        ];

        bindel = [
          ", XF86AudioRaiseVolume, exec, dms ipc call audio increment 5"
          ", XF86AudioLowerVolume, exec, dms ipc call audio decrement 5"
          ", XF86MonBrightnessUp, exec, dms ipc call brightness increment 5"
          ", XF86MonBrightnessDown, exec, dms ipc call brightness decrement 5"
        ];

        bindl = [
          ", XF86AudioMute, exec, dms ipc call audio mute"
          ", XF86AudioMicMute, exec, dms ipc call audio micmute"
          ", XF86AudioPlay, exec, dms ipc call mpris playPause"
          ", XF86AudioNext, exec, dms ipc call mpris next"
          ", XF86AudioPrev, exec, dms ipc call mpris previous"
        ];
      };
    };

    home.activation.ensureHyprlandMonitorConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p "$HOME/.config/hypr"
      if [[ ! -e "$HOME/.config/hypr/monitors.conf" ]]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 ${initialMonitorConfig} "$HOME/.config/hypr/monitors.conf"
      fi
    '';
  };
}
