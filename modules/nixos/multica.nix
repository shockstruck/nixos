# Multica agent runtime daemon, as a system service under a dedicated
# `multica` system user. The OS user is the boundary for dispatched runs: the
# opencode policy (./opencode-policy.nix) is advisory against a process that
# owns its own workspace root, so what the daemon may reach is decided here.
#
# The user has no `wheel`, `docker`, `libvirtd`, `networkmanager` or `i2c`
# membership and is not a Nix trusted-user; `systemd-journal` is for reading
# logs, `video`/`render` for the GPU probes. Its home holds the Multica CLI
# config, the opencode provider credential and the task workspaces, so
# `opencode auth login` and `multica login` run under it with `sudo -u multica
# -H`. No credential is declared here.
#
# opencode is the only backend the daemon exposes: MULTICA_CLAUDE_PATH and
# MULTICA_CODEX_PATH are pinned to an absolute path that never resolves, and
# MULTICA_OPENCODE_PATH to the exact opencode build. probeAgentCLIs' `probe`
# closure (multica-ai/multica server/internal/daemon/agents_probe.go, v0.4.43
# line 129: `if strings.ContainsAny(cmd, "/\\") { return AgentEntry{}, false }`)
# hard-misses a pinned path containing `/` that fails to resolve, with no
# fallback to PATH.
#
# ConditionPathExists keeps the unit inert until `multica login` writes the
# CLI config (server/internal/cli/config.go:13, ".multica/config.json" under
# the home). MULTICA_DAEMON_AUTO_UPDATE=false stops the self-update poll
# (server/internal/daemon/config.go:600); the store binary is read-only.
#
# Write paths, for ProtectSystem=strict: the daemon writes under $HOME/.multica
# (cli/config.go:280-292), MULTICA_WORKSPACES_ROOT (daemon/config.go:755-775,
# including the `.repos` cache, daemon.go:637) and per-task temp dirs under
# /tmp (daemon.go:9817-9838), which it hands to opencode as TMPDIR
# (daemon.go:176). opencode derives every global path from xdg-basedir under
# $HOME plus os.tmpdir() (anomalyco/opencode v1.18.31
# packages/core/src/global.ts:10-15), installs plugins under those config dirs
# and its cache (core/src/npm.ts:79), and otherwise writes only inside the task
# workdir. PrivateTmp gives both a private /tmp and /var/tmp; the home is the
# only other writable path.
{ config, lib, pkgs, ... }:
let
  home = config.users.users.multica.home;
in
{
  users.groups.multica = { };

  users.users.multica = {
    isSystemUser = true;
    group = "multica";
    description = "Multica agent runtime";
    home = "/var/lib/multica";
    createHome = true;
    homeMode = "700";
    shell = pkgs.bashInteractive;
    extraGroups = [ "systemd-journal" "video" "render" ];
  };

  environment.systemPackages = [
    pkgs.multica-cli
    pkgs.opencode
  ];

  systemd.services.multica-daemon = {
    description = "Multica agent runtime daemon";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "${home}/.multica/config.json";

    # PATH is set below; the default path would conflict with it.
    enableDefaultPath = false;
    environment = {
      HOME = home;
      MULTICA_DAEMON_AUTO_UPDATE = "false";
      MULTICA_OPENCODE_PATH = lib.getExe pkgs.opencode;
      MULTICA_CLAUDE_PATH = "/var/empty/multica-disabled/claude";
      MULTICA_CODEX_PATH = "/var/empty/multica-disabled/codex";
      MULTICA_WORKSPACES_ROOT = "${home}/multica_workspaces";
      PATH = "/run/wrappers/bin:/run/current-system/sw/bin";
    };

    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.multica-cli} daemon start --foreground";
      User = "multica";
      Group = "multica";
      Restart = "on-failure";
      RestartSec = 10;

      NoNewPrivileges = true;
      # /home, /root and /run/user are unreachable whatever their modes.
      ProtectHome = true;
      PrivateTmp = true;
      ProtectKernelTunables = true;
      RestrictSUIDSGID = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ home ];
    };
  };
}
