# stasis — Wayland idle manager (saltnpepper97/stasis) that drives Noctalia's
# shell-native lock screen (noctalialock) as the workstation's single, effective
# locker (SHOA-1002 replacing swayidle; SHOA-1026 replacing the standalone
# locker).
#
# stasis owns all idle behaviour so there is exactly one idle manager. It runs
# a deterministic, sequential timer plan mirroring the previous swayidle timings
# (SHOA-993/997): lock at 300 s, blank the monitors at 330 s, suspend at 1800 s
# (all absolute from idle start). Because stasis step timeouts are *relative to
# the previous step firing* (see stasis(5) — "Seconds relative to the previous
# enabled step firing"), the blank/suspend timeouts below are offsets:
#   lock_screen   300               -> 300 s absolute
#   blank_display  30 (after lock)  -> 330 s absolute
#   suspend      1470 (after blank) -> 1800 s absolute
#
# Locking semantics are preserved with noctalialock as the only locker:
#   - idle timeout locks via the `lock_screen` step running
#     `noctalia msg session lock` (Noctalia's ext-session-lock lock screen)
#   - pre-sleep (lid close / `systemctl suspend`, including stasis's own suspend
#     step) locks via `prepare_sleep_command`, which fires on logind
#     PrepareForSleep(true) — this replaces swayidle's `before-sleep` handler and
#     requires `enable_loginctl_integration true`
#   - the lock IPC is idempotent (Noctalia's LockScreen::lock() is a no-op while
#     already active), so repeated triggers (manual Mod+L, idle, pre-sleep) never
#     stack a second locker — the old PID guard is gone with it
#
# Unlike swayidle, stasis does NOT run a locker in response to an external
# `loginctl lock-session` (it only tracks logind LockedHint). The manual lock
# bind therefore spawns the locker directly (Mod+L in modules/home/niri.nix now
# points at the same noctalialock invocation).
#
# The stasis Home Manager module is provided by the upstream flake input
# (`flake.inputs.stasis.homeModules.default`, wired in flake.nix). The previous
# standalone locker and its PAM entry are removed (SHOA-1026): noctalialock
# authenticates through the standard `login` PAM service, so no per-locker PAM
# entry is required. DankMaterialShell's competing lock/idle stays disabled in
# dank-material-shell.nix so the two idle managers do not fight.
{ pkgs
, lib
, config
, flake
, ...
}:
let
  # noctalialock launcher (SHOA-1026): Noctalia's shell-native lock screen
  # (ext-session-lock-v1), invoked via the shell's IPC CLI. The idle step, the
  # pre-sleep hook, and the manual Mod+L bind all converge on this single
  # invocation; Noctalia's lock is idempotent while a lock is active, so the
  # old PID guard is no longer needed. Absolute store path so the stasis
  # service PATH is irrelevant.
  lockScript = pkgs.writeShellScript "noctalialock" ''
    exec ${config.programs.noctalia.package}/bin/noctalia msg session lock
  '';
  niri = "${config.programs.niri.package}/bin/niri";
  systemctl = "${pkgs.systemd}/bin/systemctl";
in
{
  imports = [ flake.inputs.stasis.homeModules.default ];

  config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    services.stasis = {
      enable = true;

      # RUNE configuration (written to ~/.config/stasis/stasis.rune). Absolute
      # store paths are used for every command so the service PATH is irrelevant.
      extraConfig = ''
        @description "ShockStruck idle plan (SHOA-1002) — single manager, noctalialock locker"

        default:
          # Subscribe to logind PrepareForSleep so `prepare_sleep_command` fires
          # before an externally-initiated (or stasis-initiated) suspend.
          enable_loginctl_integration true

          # Honor session-bus idle inhibitors (browsers, video calls, portal
          # clients). This is the one intentional upgrade over swayidle, which
          # only honored the Wayland idle-inhibit protocol; timings and the
          # locker are otherwise preserved.
          enable_dbus_inhibit true

          # No audio-based inhibition — keep swayidle's pure-timer semantics
          # (the Wayland idle-inhibit protocol is still honored regardless).
          monitor_media false

          # Keep the absolute timings exact (no per-step debounce offset).
          debounce_seconds 0

          # Lock before sleep (lid close, `systemctl suspend`, or the suspend
          # step below), mirroring swayidle's before-sleep handler.
          prepare_sleep_command "${lockScript}"

          # Lock after 5 minutes idle.
          lock_screen:
            timeout 300
            command "${lockScript}"
          end

          # Blank the monitors 30 s after the lock (330 s absolute). niri powers
          # the outputs back on automatically on input, so no resume command is
          # required.
          blank_display:
            timeout 30
            command "${niri} msg action power-off-monitors"
          end

          # Suspend at 1800 s absolute (1470 s after the blank step fired).
          suspend:
            timeout 1470
            command "${systemctl} suspend"
          end
        end
      '';
    };
  };
}
