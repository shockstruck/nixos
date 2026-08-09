{ pkgs, lib, ... }:
{
  config = lib.mkIf pkgs.stdenv.isLinux {
    wayland.windowManager.hyprland = {
      enable = true;
      systemd.enable = true;
      settings = {
        # Preferred mode, automatic placement, scale 1.
        monitor = [ ",preferred,auto,1" ];

        "$mainMod" = "SUPER";

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

          # Vast Shell (Quickshell) global shortcuts.
          "$mainMod, Space, global, quickshell:appLauncher"
          "$mainMod, S, global, quickshell:QuickSettings"
          "$mainMod, C, global, quickshell:clipboard"
          "$mainMod, W, global, quickshell:wallpaperSwitcher"
          "$mainMod SHIFT, E, global, quickshell:session"
        ];
      };
    };
  };
}
