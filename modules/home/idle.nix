# Idle is Noctalia's own idle manager, driving its shell-native lock screen
# (ext-session-lock) as the workstation's single locker. It replaces
# hypridle, which cannot keep its lock-before-sleep guarantee under niri:
# `inhibit_sleep = 3` needs the hyprland-lock-notify-v1 protocol, and without
# it hypridle (0.1.8, src/core/Hypridle.cpp) leaves sleep uninhibited, so the
# machine could suspend before the lock surface is up. Noctalia's idle
# manager is compositor-agnostic: ext-idle-notify-v1 for the timers, logind
# for sleep and locking, and its niri backend for powering outputs off.
#
# This module is what turns idle on; the console's Home Manager profile does
# not import it, so the console desktop never idles into a lock.
#
# Plan (absolute from idle start, same timings as before):
#   300 s  lock              -> Noctalia lock screen
#   330 s  screen-off        -> outputs off, back on at first input
#   1800 s lock-and-suspend  -> lock (already held) + suspend
# Each action is preceded by Noctalia's default 2 s fade to the surface
# color (idle.pre_action_fade_seconds), which any input cancels.
#
# Every behaviour's timer is re-armed when the session locks or unlocks
# (IdleManager::setSessionLocked; smithay starts each new idle notification's
# timer at creation), so while locked the `locked_timeout` values apply, and
# they are set so the plan above stays absolute: screen-off 30 s and suspend
# 1500 s after the 300 s idle lock. A manual lock (SUPER+L) gets the same
# 30 s screen-off and 1500 s suspend.
#
# Every lock path converges on Noctalia's idempotent lock:
#   - idle:   the lock behaviour above
#   - sleep:  lockscreen.lock_before_suspend (Noctalia's default, set
#             explicitly in modules/home/noctalia.nix) holds a logind delay
#             inhibitor on every route into sleep (idle suspend, `systemctl
#             suspend`, undocked lid close via logind HandleLidSwitch) until
#             the lock surface is up, so the machine never sleeps unlocked
#   - manual: SUPER+L in modules/home/niri.nix runs `noctalia msg session
#             lock`; `loginctl lock-session` from anywhere else reaches the
#             same lock through logind's Lock signal
#
# Inhibitors: Wayland idle-inhibit (handled by niri, so no idle event fires),
# org.freedesktop.ScreenSaver (browsers, video calls, portal clients) and
# `systemd-inhibit --what=idle` (logind BlockInhibited) are all honoured by
# Noctalia; no media or audio heuristics.
{ pkgs
, lib
, ...
}:
{
  config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    programs.noctalia.settings.idle.behavior = {
      lock = {
        enabled = true;
        timeout = 300;
        action = "lock";
      };
      screen-off = {
        enabled = true;
        timeout = 330;
        locked_timeout = 30;
        action = "screen_off";
      };
      lock-and-suspend = {
        enabled = true;
        timeout = 1800;
        locked_timeout = 1500;
        action = "lock_and_suspend";
      };
    };
  };
}
