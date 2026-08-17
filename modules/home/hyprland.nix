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

        "$mainMod" = "SUPER";

        # Plugin defaults to inactive; middle-button autoscroll starts only
        # after the SUPER+CTRL+A toggle.
        plugin.hypr_autoscroll.direct_activation = false;

        bind = [
          "$mainMod, Return, exec, foot"
          "$mainMod, Q, killactive"

          "$mainMod, left, movefocus, l"
          "$mainMod, right, movefocus, r"
          "$mainMod, up, movefocus, u"
          "$mainMod, down, movefocus, d"

          "$mainMod, 1, workspace, 1"
          "$mainMod, 2, workspace, 2"
          "$mainMod, 3, workspace, 3"
          "$mainMod, 4, workspace, 4"
          "$mainMod, 5, workspace, 5"

          "$mainMod SHIFT, 1, movetoworkspace, 1"
          "$mainMod SHIFT, 2, movetoworkspace, 2"
          "$mainMod SHIFT, 3, movetoworkspace, 3"
          "$mainMod SHIFT, 4, movetoworkspace, 4"
          "$mainMod SHIFT, 5, movetoworkspace, 5"

          # illogical-impulse Quickshell surfaces.
          "$mainMod, Space, global, quickshell:overviewToggle"
          "$mainMod, S, exec, quickshell -p $HOME/.config/quickshell/ii/settings.qml"
          "$mainMod, C, global, quickshell:overviewClipboardToggle"
          "$mainMod, W, exec, $HOME/.config/quickshell/ii/scripts/colors/switchwall.sh --choose"
          "$mainMod SHIFT, E, global, quickshell:sessionToggle"
          "$mainMod, A, global, quickshell:sidebarLeftToggle"
          "$mainMod, N, global, quickshell:sidebarRightToggle"
          "$mainMod, M, global, quickshell:mediaControlsToggle"
          "$mainMod, slash, global, quickshell:cheatsheetToggle"

          # Keep SUPER+A for ii's AI sidebar and move middle-button autoscroll.
          "$mainMod CTRL, A, hypr-autoscroll:middle-mode, toggle"
        ];
      };
    };
  };
}
