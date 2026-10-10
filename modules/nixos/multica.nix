# Multica agent runtime daemon, as a system service under a dedicated
# `multica` system user. The OS user is the boundary for dispatched runs: the
# opencode policy (./opencode-policy.nix) is advisory against a process that
# owns its own workspace root, so what the daemon may reach is decided here.
#
# The user has no `wheel`, `docker`, `libvirtd`, `networkmanager` or `i2c`
# membership and is not a Nix trusted-user; `systemd-journal` is for reading
# logs, `video`/`render` for the GPU probes. Its home holds the Multica CLI
# config, the opencode provider credential and the task workspaces, so
# `opencode auth login` and `multica login` run under it with
# `sudo -u multica -H`. No credential is declared here.
#
# MULTICA_SERVER_URL pins the daemon to the ShockStruck API whatever
# config.json holds: `daemon start` resolves the server as --server-url, then
# MULTICA_SERVER_URL, then config.json (multica-ai/multica v0.6.1
# server/cmd/multica/cmd_daemon.go:720-728). The unit environment does not
# reach an interactive `sudo -u multica` shell, so the login repeats it as a
# flag, which `login --token` also writes to config.json as server_url
# (cmd_auth.go:436-454):
#
#   sudo -u multica -H multica --server-url https://multica-api.panic.ac login --token
#
# The token flow needs no app_url; the CLI reads it only to open the
# workspace-creation page when the account has no workspace (cmd_login.go:157).
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
#
# Kevin's game library is the one path under /home a run can see.
# ProtectHome=tmpfs hides /home, /root and /run/user behind empty read-only
# tmpfs mounts, and BindReadOnlyPaths= mounts the library back into that view
# read-only (systemd.exec(5): tmpfs "is useful to hide home directories not
# relevant to the processes invoked by the unit, while still allowing
# necessary directories to be made visible when listed in BindPaths= or
# BindReadOnlyPaths="). The leading `-` skips the mount on a host without the
# directory. The ACL gives the user read on files whose modes exclude
# "other"; nothing grants it /home/kevin, so outside the unit, where that home
# is mode 700, the ACL reaches nothing. tmpfiles re-applies it recursively at
# boot and on activation without following symlinks (tmpfiles.d(5) `A+`), and
# the default ACL covers what is created in between.
{ config, lib, pkgs, ... }:
let
  home = config.users.users.multica.home;
  gamesDir = "${config.users.users.kevin.home}/UGI_Games";
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
    # Probes on the operator's allowlist (./opencode-policy.nix) that the base
    # system lacks: lsof, vulkaninfo, eglinfo.
    pkgs.lsof
    pkgs.vulkan-tools
    pkgs.mesa-demos
  ];

  systemd.tmpfiles.settings."10-multica-games".${gamesDir}."A+".argument =
    "u:multica:rX,d:u:multica:rX";

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
      MULTICA_SERVER_URL = "https://multica-api.panic.ac";
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
      # /home, /root and /run/user are empty whatever their modes, apart from
      # the read-only game library.
      ProtectHome = "tmpfs";
      BindReadOnlyPaths = [ "-${gamesDir}" ];
      PrivateTmp = true;
      ProtectKernelTunables = true;
      RestrictSUIDSGID = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ home ];
    };
  };
}
