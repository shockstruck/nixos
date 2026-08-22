# swayidle — idle daemon that makes swaylock the workstation's overall
# locker (SHOA-993), adapted for niri (SHOA-997).
#
# swayidle owns all idle behaviour so there is a single idle manager:
#   - any `loginctl lock-session` (manual Super+L, DMS power menu, remote)
#     raises the systemd-logind `lock` signal, which swayidle handles by
#     running swaylock
#   - idle timeout locks the session (via `loginctl lock-session`, which in
#     turn runs swaylock through the `lock` handler)
#   - before sleep locks
#   - screen blanks (niri `power-off-monitors`) and suspends on the same
#     timings the Hyprland build used (300 s lock / 330 s blank / 1800 s
#     suspend). niri restores the monitors automatically on input, so no
#     explicit power-on resume command is required.
#
# This replaces the Hyprland-specific hypridle (`hyprctl dispatch dpms`,
# `hyprland-session.target`), which does not evaluate under niri. swaylock
# and its PAM entry are unchanged (see swaylock.nix + modules/nixos/gui/
# niri.nix). DankMaterialShell's competing lock/idle stays disabled in
# dank-material-shell.nix so the two idle managers do not fight.
{ pkgs
, lib
, config
, ...
}:
let
  swaylock = "${pkgs.procps}/bin/pidof swaylock || ${pkgs.swaylock-effects}/bin/swaylock";
  loginctl = "${pkgs.systemd}/bin/loginctl";
  systemctl = "${pkgs.systemd}/bin/systemctl";
  niri = "${config.programs.niri.package}/bin/niri";
in
{
  config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    services.swayidle = {
      enable = true;
      systemdTarget = "graphical-session.target";

      events = [
        # `loginctl lock-session` (manual Super+L, DMS power menu, or the
        # idle timeout below) and pre-sleep both run swaylock.
        { event = "lock"; command = swaylock; }
        { event = "before-sleep"; command = "${loginctl} lock-session"; }
      ];

      timeouts = [
        # Lock after 5 minutes idle (mooniri/DMS prior lock timing).
        {
          timeout = 300;
          command = "${loginctl} lock-session";
        }
        # Blank the display shortly after the lock triggers.
        {
          timeout = 330;
          command = "${niri} msg action power-off-monitors";
        }
        # Suspend after 30 minutes idle (DMS prior suspend timing).
        {
          timeout = 1800;
          command = "${systemctl} suspend";
        }
      ];
    };
  };
}
