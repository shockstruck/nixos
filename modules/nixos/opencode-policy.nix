# opencode managed config: the policy for runs the Multica daemon
# (./multica.nix) dispatches to opencode. The daemon starts
# `opencode run --dangerously-skip-permissions`, which auto-approves every
# "ask", so only "allow" and "deny" bind, and the managed file
# /etc/opencode/opencode.json is the top config tier
# (anomalyco/opencode v1.18.31 packages/opencode/src/config/managed.ts:27,
# config/config.ts:530-535). Home Manager's programs.opencode.settings writes
# only the user file, so this is a NixOS module.
#
# It is advisory, not the boundary: the agent owns its workspace root, and a
# lower tier can still append rules after these (a `mode.<name>` entry is
# merged after the managed tier, config/config.ts:550). The `multica` system
# user in ./multica.nix is what bounds a run. The policy keeps the model
# inside that: every tool starts from deny, `bash` is an allowlist of
# read-only commands, and the workspace allow in `edit` excludes the files
# opencode loads as config or instructions, so the agent cannot plant one
# that disables itself. `disable = false` is pinned for the same reason.
#
# Every rule sits on the named agent `multica-operator`, which Multica selects
# with `--agent multica-operator`; no rule is top-level, because the managed
# tier also applies to interactive opencode sessions. The guard plugin is
# top-level and checks the agent itself.
#
# Rule order is load-bearing: opencode keeps the file's key order and the last
# matching rule wins (permission/index.ts:28-37, `findLast`), with `*`
# matching any run of characters, `/` and spaces included, and a trailing
# ` *` also matching no arguments (util/wildcard.ts:3-19). builtins.toJSON
# sorts attribute names, so `ordered` objects are rendered in list order.
#
# Path patterns: `~/` is expanded to the home directory
# (permission/index.ts:178-184). The edit/write/read tools pass a path
# relative to the project worktree, which is `/` for a task workdir that is not
# a git repository (tool/read.ts:257, tool/write.ts:56,
# project/instance-context.ts:20-22), so every path is also written without
# its leading slash. external_directory receives an absolute directory glob
# for reads and for the arguments of `cat` and the other file commands in
# tool/shell.ts:29-50 (tool/external-directory.ts:28-38, tool/shell.ts:
# 397-404). `head`, `tail`, `grep` and the rest of the allowlist are not in
# that set, so their path arguments are checked by nothing but the OS user.
{ config, lib, ... }:
let
  ordered = pairs: { __ordered = pairs; };

  render = v:
    if builtins.isAttrs v && v ? __ordered then
      "{" + lib.concatMapStringsSep "," (p: "${builtins.toJSON p.name}:${render p.value}") v.__ordered + "}"
    else if builtins.isAttrs v then
      "{" + lib.concatStringsSep "," (lib.mapAttrsToList (n: x: "${builtins.toJSON n}:${render x}") v) + "}"
    else if builtins.isList v then
      "[" + lib.concatMapStringsSep "," render v + "]"
    else
      builtins.toJSON v;

  rules = action: patterns: map (p: lib.nameValuePair p action) patterns;

  # Each command as both `X` and `X *`.
  withArgs = lib.concatMap (c: [ c "${c} *" ]);

  # The whole bash surface: everything else falls to the leading `"*"` deny.
  allowedCommands = [
    "hostname"
    "id"
    "uname"
    "uptime"
    "date"
    "journalctl"
    "systemctl status"
    "systemctl cat"
    "systemctl list-units"
    "systemctl list-timers"
    "systemctl show"
    "systemctl list-unit-files"
    "systemctl list-dependencies"
    "systemctl is-active"
    "systemctl is-enabled"
    "systemctl is-failed"
    "systemd-analyze time"
    "systemd-analyze blame"
    "systemd-analyze critical-chain"
    "systemd-analyze security"
    "systemd-analyze cat-config"
    "coredumpctl list"
    "coredumpctl info"
    "dmesg"
    "loginctl list-sessions"
    "loginctl show-session"
    "loginctl session-status"
    "loginctl list-users"
    "nmcli device show"
    "nmcli device status"
    "nmcli connection show"
    "nmcli general status"
    "ip"
    "ss"
    "lsblk"
    "lspci"
    "lsusb"
    "free"
    "df"
    "sensors"
    "nvidia-smi"
    "rocm-smi"
    "lscpu"
    "lsmod"
    "modinfo"
    "vulkaninfo"
    "eglinfo"
    "ps"
    "pgrep"
    "top -b -n1"
    "lsof"
    "findmnt"
    "flatpak list"
    "flatpak info"
    "flatpak ps"
    "flatpak remotes"
    "flatpak history"
    "nix-store --query"
    "nix-store -q"
    "ls"
    "cat"
    "grep"
    "readlink"
    "head"
    "tail"
    "wc"
    "stat"
    "file"
    "du"
    "getfacl"
    "which"
    "multica issue get"
    "multica issue comment list"
    "multica issue comment add"
  ];

  # Denied after the allows, so they win over any allowed command: redirection,
  # command substitution (both forms), Nix settings passed to the daemon,
  # attachments, and every flag that points an allowed command at another host:
  # a URL, the multica CLI's server/profile/workspace overrides, a Nix store or
  # substituter, systemctl/loginctl/systemd-analyze `-H`/`--host`, which run
  # ssh, and the arguments that make ss, lspci or lsof resolve a name the
  # agent chose over DNS. Then the forms that turn an allowed read into a
  # write: vulkaninfo's output file, and dmesg's clear and console flags,
  # matched on the bare letter as for lspci so a bundled short flag cannot slip
  # past (`journalctl -k` is the unrestricted kernel log).
  deniedForms = [
    "*>*"
    "*$(*"
    "*`*"
    "* --option *"
    "*--attachment*"
    "*://*"
    "* --server-url*"
    "* --profile*"
    "* --workspace-id*"
    "* --store*"
    "* --eval-store*"
    "*substituters*"
    "systemctl *H*"
    "systemctl *--host*"
    "loginctl *H*"
    "loginctl *--host*"
    "ss *dst*"
    "ss *src*"
    "ss *F*"
    "ss *--filter*"
    "lspci *q*"
    "lspci *Q*"
    "lspci *O*"
    "systemd-analyze *H*"
    "systemd-analyze *--host*"
    "lsof *@*"
    "vulkaninfo *-o*"
    "dmesg *c*"
    "dmesg *C*"
    "dmesg *D*"
    "dmesg *E*"
    "dmesg *n*"
  ];

  # The daemon's home (./multica.nix). A pattern is written absolute, relative
  # to `/` (what the read and edit tools match against), and as `~/`, which
  # opencode expands to the running process's home.
  multicaHome = config.users.users.multica.home;
  relative = lib.removePrefix "/";
  homePaths = p: [ "~/${p}" "${multicaHome}/${p}" (relative "${multicaHome}/${p}") ];
  # Secret paths also in every other user's home.
  secretPaths = p: homePaths p ++ [ "/home/*/${p}" "home/*/${p}" "/root/${p}" "root/${p}" ];

  workspaceRoots = homePaths "multica_workspaces/**";

  # Kevin's game library, bound read-only into the daemon's view (./multica.nix).
  gamesDir = "${config.users.users.kevin.home}/UGI_Games";
  gamesPaths = [ gamesDir "${gamesDir}/**" ];

  systemPaths = [
    "/etc/**"
    "/run/current-system/**"
    "/nix/**"
    "/var/log/**"
    "/sys/**"
  ];

  allowedPaths = systemPaths ++ gamesPaths ++ map relative (systemPaths ++ gamesPaths) ++ workspaceRoots;

  deniedPaths = lib.concatMap secretPaths [
    ".ssh/**"
    ".kube/**"
    ".talos/**"
    ".config/sops/**"
    ".config/gh/**"
    ".multica/**"
    ".local/share/opencode/**"
    ".gnupg/**"
    ".aws/**"
  ]
  ++ [
    "*.agekey"
    "*.key"
    "*.pem"
    "*.env"
    "*.env.*"
  ];

  # Deny everything, then allow the system and workspace paths, then deny
  # secrets where the two overlap (`/etc/**/*.pem`).
  pathRules = ordered (rules "deny" [ "*" ] ++ rules "allow" allowedPaths ++ rules "deny" deniedPaths);

  # Files opencode loads as config or instructions: an agent that could write
  # them could disable or reorder its own rules.
  configFiles = [
    "*opencode.json"
    "*opencode.jsonc"
    "*/.opencode/*"
    ".opencode/*"
    "*AGENTS.md"
  ];

  policy = {
    "$schema" = "https://opencode.ai/config.json";
    share = "disabled";
    autoupdate = false;
    # Top-level because opencode has no per-agent plugins. The guard
    # (./opencode-guard/guard.js) checks the operator's whole bash command
    # string, which the bash patterns below cannot, and is inert for every
    # other agent. A path plugin loads from the store with no install step.
    plugin = [ "file://${./opencode-guard/guard.js}" ];
    agent.multica-operator = ordered [
      (lib.nameValuePair "mode" "primary")
      (lib.nameValuePair "disable" false)
      (lib.nameValuePair "model" "deepseek/deepseek-flash")
      (lib.nameValuePair "prompt" (lib.concatStringsSep " " [
        "You are the NixOS Workstation Operator, a read-only diagnostics agent dispatched by Multica to this workstation."
        "You collect evidence from the machine itself (journal entries, unit state, session, process, kernel, hardware and graphics probes, coredumps, Flatpak state, configuration under /etc and /run/current-system, and the game library under ${gamesDir}, which is read-only)"
        "and report the exact commands you ran with their raw output."
        "You never change the machine: no activation, installation, service or package changes, privilege escalation, network sends, or writes outside your task workspace."
        "This machine's opencode policy denies those commands; a denial is a finding to report, never something to route around."
      ]))
      (lib.nameValuePair "permission" (ordered [
        (lib.nameValuePair "bash" (ordered (
          rules "deny" [ "*" ]
          ++ rules "allow" (withArgs allowedCommands)
          ++ rules "deny" deniedForms
        )))
        (lib.nameValuePair "edit" (ordered (
          rules "deny" [ "*" ]
          ++ rules "allow" workspaceRoots
          ++ rules "deny" configFiles
        )))
        (lib.nameValuePair "read" pathRules)
        (lib.nameValuePair "external_directory" pathRules)
        (lib.nameValuePair "webfetch" "deny")
        (lib.nameValuePair "websearch" "deny")
        (lib.nameValuePair "task" "deny")
        (lib.nameValuePair "question" "deny")
      ]))
    ];
  };
in
{
  environment.etc."opencode/opencode.json".text = render policy;
}
