# opencode managed config: the deny policy for runs the Multica daemon
# (modules/home/multica.nix) dispatches to opencode. The daemon starts
# `opencode run --dangerously-skip-permissions`, which auto-approves every
# "ask", so an explicit "deny" is the only rule that binds, and the managed
# file /etc/opencode/opencode.json is the only tier a user file, a checked-out
# repo's opencode.json or OPENCODE_CONFIG_CONTENT cannot override
# (anomalyco/opencode v1.18.31 packages/opencode/src/config/managed.ts:27,
# config/config.ts:530-535). Home Manager's programs.opencode.settings writes
# only the user file, so this is a NixOS module.
#
# Everything sits on the named agent `multica-operator`, which Multica selects
# with `--agent multica-operator`; nothing is top-level, because the managed
# tier also applies to interactive opencode sessions.
#
# Rule order is load-bearing: opencode keeps the file's key order and the last
# matching rule wins (permission/index.ts:28-37, `findLast`). builtins.toJSON
# sorts attribute names, which would put the `*.pem` deny ahead of the
# `/etc/**` allow, so `ordered` objects are rendered in list order instead.
#
# Path patterns: `~/` is expanded to the home directory
# (permission/index.ts:178-184). The edit/write/read tools pass a path
# relative to the project worktree, which is `/` for a task workdir that is not
# a git repository (tool/write.ts:56, project/instance-context.ts:20-22), so
# the workspaces allow is also written without its leading slash. Secret
# directories are denied through external_directory, which receives an
# absolute directory glob for reads and for `cat`/`cp`/`rm`-style shell
# arguments outside the workdir (tool/external-directory.ts:28-38,
# tool/shell.ts:397-404).
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

  deniedCommands = [
    "nixos-rebuild"
    "nixos-install"
    "nixos-enter"
    "home-manager"
    "disko"
    "nix build"
    "nix run"
    "nix shell"
    "nix develop"
    "nix profile"
    "nix-env"
    "nix-shell"
    "nix flake update"
    "nix flake check"
    "nix-collect-garbage"
    "nix-store --gc"
    "nix-store --delete"
    "just run"
    "just check"
    "just update"
    "just dev"
    "sudo"
    "su"
    "pkexec"
    "doas"
  ]
  ++ map (verb: "systemctl ${verb}") [
    "start"
    "stop"
    "restart"
    "enable"
    "disable"
    "mask"
    "daemon-reload"
    "poweroff"
    "reboot"
    "kexec"
  ]
  ++ [
    "reboot"
    "shutdown"
    "poweroff"
    "halt"
    "dd"
    "mkfs*"
    "wipefs"
    "parted"
    "sgdisk"
    "sfdisk"
    "cryptsetup"
    "systemd-cryptenroll"
    "tpm2*"
    "mount"
    "umount"
    "rm -rf"
    "chmod"
    "chown"
    "kill"
    "pkill"
    "killall"
    "ssh"
    "scp"
    "rsync"
    "curl"
    "wget"
    "gh"
    "git push"
    "git commit"
    "kubectl"
    "talosctl"
    "flux"
    "helm"
    "sops"
    "age"
    "multica daemon"
    "multica login"
    "opencode"
  ];

  workspaceRoots = map (user: "${config.users.users.${user}.home}/multica_workspaces/**") config.myusers;

  allowedPaths = [
    "/etc/**"
    "/run/current-system/**"
    "/nix/**"
    "/var/log/**"
    "/proc/**"
    "/sys/**"
    "~/multica_workspaces/**"
  ];

  deniedPaths = [
    "~/.ssh/**"
    "~/.kube/**"
    "~/.talos/**"
    "~/.config/sops/**"
    "~/.config/gh/**"
    "~/.multica/**"
    "~/.local/share/opencode/**"
    "~/.gnupg/**"
    "~/.aws/**"
    "*.agekey"
    "*.key"
    "*.pem"
    "*.env"
    "*.env.*"
  ];

  # Allows first so a deny wins where the two overlap (`/etc/**/*.pem`).
  pathRules = ordered (rules "allow" allowedPaths ++ rules "deny" deniedPaths);

  policy = {
    "$schema" = "https://opencode.ai/config.json";
    share = "disabled";
    autoupdate = false;
    agent.multica-operator = ordered [
      (lib.nameValuePair "mode" "primary")
      (lib.nameValuePair "model" "deepseek/deepseek-flash")
      (lib.nameValuePair "prompt" (lib.concatStringsSep " " [
        "You are the NixOS Workstation Operator, a read-only diagnostics agent dispatched by Multica to this workstation."
        "You collect evidence from the machine itself (journal entries, unit state, hardware and session probes, configuration under /etc and /run/current-system)"
        "and report the exact commands you ran with their raw output."
        "You never change the machine: no activation, installation, service or package changes, privilege escalation, network sends, or writes outside your task workspace."
        "This machine's opencode policy denies those commands; a denial is a finding to report, never something to route around."
      ]))
      (lib.nameValuePair "permission" (ordered [
        (lib.nameValuePair "bash" (ordered (rules "allow" [ "*" ] ++ rules "deny" (withArgs deniedCommands))))
        (lib.nameValuePair "edit" (ordered (
          rules "deny" [ "*" ]
          ++ rules "allow" ([ "~/multica_workspaces/**" ] ++ map (lib.removePrefix "/") workspaceRoots)
        )))
        (lib.nameValuePair "read" pathRules)
        (lib.nameValuePair "external_directory" pathRules)
        (lib.nameValuePair "task" "deny")
        (lib.nameValuePair "question" "deny")
      ]))
    ];
  };
in
{
  environment.etc."opencode/opencode.json".text = render policy;
}
