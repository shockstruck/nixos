# Multica agent runtime daemon, as a systemd user service under `kevin` so it
# shares the user session (Hyprland/Noctalia, the journal). Installs
# `pkgs.opencode` itself (not from `./packages.nix`, which the console profile
# doesn't import) so `opencode auth login` and the daemon both have it, on
# every host this module reaches.
#
# opencode is the only backend the daemon exposes: MULTICA_CLAUDE_PATH and
# MULTICA_CODEX_PATH are pinned to an absolute path that never resolves, and
# MULTICA_OPENCODE_PATH is pinned to the exact opencode build. probeAgentCLIs'
# `probe` closure (multica-ai/multica server/internal/daemon/agents_probe.go,
# v0.4.43 line 129, v0.5.3 line 131: `if strings.ContainsAny(cmd, "/\\")
# { return AgentEntry{}, false }`) hard-misses a pinned path containing `/`
# that fails to resolve — it never falls back to PATH or the login shell —
# so claude/codex stay excluded even though PATH below still carries
# `${config.home.profileDirectory}/bin`. That entry (and `/run/wrappers/bin`,
# `/run/current-system/sw/bin`) is kept for `git`, `ssh` and the rest of the
# system tools opencode itself needs.
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
{ config, lib, pkgs, ... }:
{
  home.packages = [
    pkgs.multica-cli
    pkgs.opencode
  ];

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
        "MULTICA_OPENCODE_PATH=${lib.getExe pkgs.opencode}"
        "MULTICA_CLAUDE_PATH=/var/empty/multica-disabled/claude"
        "MULTICA_CODEX_PATH=/var/empty/multica-disabled/codex"
        "PATH=${config.home.profileDirectory}/bin:/run/wrappers/bin:/run/current-system/sw/bin"
      ];
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
