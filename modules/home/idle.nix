# hypridle — Hyprland's idle daemon, driving Noctalia's shell-native lock
# screen (ext-session-lock) as the workstation's single locker. It replaces
# stasis: with the laptop docked and the lid closed, stasis paused its whole
# idle plan (no idle lock, DPMS or suspend) and offers no way to turn that
# off; hypridle has no lid handling at all, so the listeners below keep
# counting whatever the lid does.
#
# Plan (absolute from idle start, unchanged timings):
#   300 s  lock    -> `loginctl lock-session`; logind turns it into the Lock
#                    signal hypridle answers with general.lock_cmd
#   330 s  dpms    -> `hyprctl dispatch dpms off`, back on at first input
#   1800 s suspend -> `systemctl suspend`
#
# Every lock path converges on one idempotent command (Noctalia's
# LockScreen::lock() is a no-op while a lock is active):
#   - idle:   the 300 s listener -> loginctl lock-session -> lock_cmd
#   - sleep:  before_sleep_cmd = loginctl lock-session fires for every route
#             into sleep (idle suspend, `systemctl suspend`, undocked lid
#             close via logind HandleLidSwitch); inhibit_sleep = 3 holds a
#             logind delay inhibitor until the lock surface is up
#             (hyprland-lock-notify-v1), so the machine never sleeps unlocked
#   - manual: SUPER+L in modules/home/hyprland.nix calls Noctalia directly;
#             `loginctl lock-session` from anywhere else works too
#
# Inhibitors: Wayland idle-inhibit, org.freedesktop.ScreenSaver (browsers,
# video calls, portal clients) and `systemd-inhibit --what=idle` are all
# honoured by hypridle's defaults; no media or audio heuristics.
#
# Absolute store paths so the systemd user service PATH is irrelevant.
# after_sleep_cmd turns the displays back on so waking does not need a
# second key press.
{ pkgs
, lib
, config
, ...
}:
let
  loginctl = "${pkgs.systemd}/bin/loginctl";
  systemctl = "${pkgs.systemd}/bin/systemctl";
  hyprctl = "${config.wayland.windowManager.hyprland.finalPackage}/bin/hyprctl";
  lockScript = pkgs.writeShellScript "noctalialock" ''
    exec ${config.programs.noctalia.package}/bin/noctalia msg session lock
  '';
in
{
  config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    services.hypridle = {
      enable = true;
      settings = {
        general = {
          lock_cmd = "${lockScript}";
          before_sleep_cmd = "${loginctl} lock-session";
          after_sleep_cmd = "${hyprctl} dispatch dpms on";
          inhibit_sleep = 3;
        };
        listener = [
          {
            timeout = 300;
            on-timeout = "${loginctl} lock-session";
          }
          {
            timeout = 330;
            on-timeout = "${hyprctl} dispatch dpms off";
            on-resume = "${hyprctl} dispatch dpms on";
          }
          {
            timeout = 1800;
            on-timeout = "${systemctl} suspend";
          }
        ];
      };
    };
  };
}
