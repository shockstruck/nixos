# Multica agent runtime daemon, as a systemd user service under `kevin` so it
# shares the user session (Hyprland/Noctalia, the journal) and the agent CLIs
# `./packages.nix` already installs (claude-code, codex, opencode).
#
# ConditionPathExists keeps the unit inert until `multica login` / `multica
# setup` writes the CLI config file — the default path Home Manager's %h
# expands to is the same one CLIConfigPathForProfile("") resolves
# (multica-ai/multica server/internal/cli/config.go:11-12,
# defaultCLIConfigPath = ".multica/config.json" under the user's home) —
# instead of crash-looping before first login.
#
# MULTICA_DAEMON_AUTO_UPDATE=false disables the daemon's periodic self-update
# poll (multica-ai/multica server/internal/daemon/config.go:602,
# boolFromEnv("MULTICA_DAEMON_AUTO_UPDATE", ...)): the store binary is
# read-only, so an in-place self-update would just fail.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = [ pkgs.multica-cli ];

  systemd.user.services.multica-daemon = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    Unit = {
      Description = "Multica agent runtime daemon";
      ConditionPathExists = "%h/.multica/config.json";
    };

    Service = {
      ExecStart = "${lib.getExe pkgs.multica-cli} daemon start --foreground";
      Restart = "on-failure";
      RestartSec = 10;
      Environment = [
        "MULTICA_DAEMON_AUTO_UPDATE=false"
        "PATH=${config.home.profileDirectory}/bin:/run/wrappers/bin:/run/current-system/sw/bin"
      ];
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
