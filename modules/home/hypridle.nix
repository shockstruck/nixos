# hypridle — idle daemon that makes swaylock the workstation's overall
# locker (SHOA-993).
#
# hypridle owns all idle behaviour so there is a single idle manager:
#   - any `loginctl lock-session` (manual SUPER+L, DMS power menu, remote)
#     runs `lock_cmd` -> swaylock
#   - idle timeout locks the session (which runs swaylock via lock_cmd)
#   - before sleep locks; after sleep restores DPMS
#   - screen blanks (DPMS) and suspends on the same timings DMS used
#     previously (300 s lock / 330 s DPMS / 1800 s suspend)
#
# DankMaterialShell's competing lock/idle is disabled in
# dank-material-shell.nix (`loginctlLockIntegration = false` plus zeroed
# lock/monitor/suspend timeouts) so the two idle managers do not fight.
{ pkgs
, lib
, config
, ...
}:
let
  swaylock = "${pkgs.procps}/bin/pidof swaylock || ${pkgs.swaylock-effects}/bin/swaylock";
  loginctl = "${pkgs.systemd}/bin/loginctl";
  systemctl = "${pkgs.systemd}/bin/systemctl";
  hyprctl = "${config.wayland.windowManager.hyprland.finalPackage}/bin/hyprctl";
in
{
  config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    services.hypridle = {
      enable = true;
      systemdTarget = "hyprland-session.target";

      settings = {
        general = {
          lock_cmd = swaylock;
          before_sleep_cmd = "${loginctl} lock-session";
          after_sleep_cmd = "${hyprctl} dispatch dpms on";
          ignore_dbus_inhibit = false;
        };

        listener = [
          {
            # Lock after 5 minutes idle (mooniri/DMS prior lock timing).
            timeout = 300;
            on-timeout = "${loginctl} lock-session";
          }
          {
            # Blank the display shortly after the lock triggers.
            timeout = 330;
            on-timeout = "${hyprctl} dispatch dpms off";
            on-resume = "${hyprctl} dispatch dpms on";
          }
          {
            # Suspend after 30 minutes idle (DMS prior suspend timing).
            timeout = 1800;
            on-timeout = "${systemctl} suspend";
          }
        ];
      };
    };
  };
}
