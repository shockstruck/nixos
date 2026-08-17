{ pkgs
, lib
, config
, flake
, ...
}:
let
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

      settings = {
        # Preferred mode, automatic placement, scale 1.
        monitor = [ ",preferred,auto,1" ];

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

          # illogical-impulse Quickshell surfaces.
          "$mainMod, Space, Shell: Toggle overview, global, quickshell:overviewToggle"
          "$mainMod, S, Shell: Open settings, exec, quickshell -p $HOME/.config/quickshell/ii/settings.qml"
          "$mainMod, C, Shell: Toggle clipboard history, global, quickshell:overviewClipboardToggle"
          "$mainMod, W, Shell: Choose wallpaper, exec, $HOME/.config/quickshell/ii/scripts/colors/switchwall.sh --choose"
          "$mainMod SHIFT, E, Shell: Toggle session menu, global, quickshell:sessionToggle"
          "$mainMod, A, Shell: Toggle AI sidebar, global, quickshell:sidebarLeftToggle"
          "$mainMod, N, Shell: Toggle right sidebar, global, quickshell:sidebarRightToggle"
          "$mainMod, M, Shell: Toggle media controls, global, quickshell:mediaControlsToggle"
          "$mainMod, slash, Shell: Toggle keybind cheatsheet, global, quickshell:cheatsheetToggle"

          # Keep SUPER+A for ii's AI sidebar and move middle-button autoscroll.
          "$mainMod CTRL, A, Utilities: Toggle middle-button autoscroll, hypr-autoscroll:middle-mode, toggle"
        ];

        bindel = [
          ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"
          ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
          ", XF86MonBrightnessUp, exec, brightnessctl set 5%+"
          ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
        ];

        bindl = [
          ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
          ", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
          ", XF86AudioPlay, exec, playerctl play-pause"
          ", XF86AudioNext, exec, playerctl next"
          ", XF86AudioPrev, exec, playerctl previous"
        ];
      };
    };
  };
}
