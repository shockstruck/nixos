# Project Alpha CI runner for the console: one disposable KVM guest per
# explicit start. Console-only and disabled by default, so with `enable =
# false` nothing here is instantiated — no user, no unit, no guest evaluation —
# and the console starts no runner and needs no credential.
#
# Enabling it needs two runtime interfaces this module does not provision:
#
#   * `egressSocket`: an AF_UNIX stream socket served by the separately
#     reviewed isolated egress gateway. systemd connects it as the service
#     manager (`OpenFile=`) and passes it to the launcher as file descriptor 3,
#     so the socket can be root-only and a missing socket fails the unit. It is
#     QEMU's only network path (`-netdev stream`): the gateway carries framed
#     Ethernet, supplies guest addressing and enforces destinations outside the
#     VM. There is no bridge, no SLiRP, no host mount and no forwarded port,
#     and the unit can create no socket of its own.
#   * `jitSocket`: a root-provisioned AF_UNIX stream socket that yields one
#     fresh, single-use GitHub encoded JIT configuration for a repository-level
#     runner on `project-alpha-rsps/server` only. systemd reads it with
#     `LoadCredential=` before exec (systemd.exec: an absolute path that
#     refers to an AF_UNIX stream socket is read once at process invocation).
#     QEMU hands the credential to the guest through fw_cfg by file path only,
#     never by value on the host command line, and the guest bootstrap feeds it
#     to `Runner.Listener` once.
#
# The broker serving `jitSocket` is not part of this module. It must
# authenticate its caller and follow these rules, which gate activation:
#
#   1. Token: request it for repository ID `1207177553` with
#      `administration: write`. The response must show
#      `repository_selection` = `selected`, exactly one repository with that ID
#      and full name `project-alpha-rsps/server`, and permissions exactly
#      `administration: write` and `metadata: read`.
#   2. Mint: POST to the constant path
#      `/repos/project-alpha-rsps/server/actions/runners/generate-jitconfig` on
#      `api.github.com` with redirects off and a fresh random runner name, and
#      accept only 201.
#   3. Repository proof: GET
#      `/repos/project-alpha-rsps/server/actions/runners/{runner.id}` with the
#      same token and redirects off, and require 200 with the same `id`, `name`
#      and label names as step 2. No field in the payload can stand in for
#      this.
#   4. Record: label names are exactly `["project-alpha-rsps-console"]` and no
#      default labels; `runner_group_id` is the default group's integer,
#      confirmed before activation and not recorded here. The step 2 value must
#      equal that integer; only when step 2 omits it is step 3's value compared,
#      and absence from both is a rejection. `ephemeral`, if present, is `true`.
#   5. Payload: decoded `AgentName` (key matched ignoring case) equals the
#      random name exactly. Never compare `runner.id` with `AgentId`. The guest
#      rules below then apply.
#   6. Any failure, timeout or odd response: send zero bytes on the socket (the
#      launcher rejects an empty credential), DELETE the runner and log a fixed
#      message only. If the ID is unknown, find the runner by its exact random
#      name. Refuse further mints until a person confirms the runner list.
#
# It also declares no organization runner group and applies no workflow/ref
# allowlist.
#
# The guest applies defence in depth on top of those checks. `gitHubUrl` may be
# absent; when present it must equal
# `https://github.com/project-alpha-rsps/server` exactly. At least one of
# `serverUrl` and `serverUrlV2` must be present and each one present must match
# a `*.actions.githubusercontent.com` service host. The job-started hook
# requires `GITHUB_REPOSITORY_ID` of `1207177553` and `GITHUB_SERVER_URL` of
# `https://github.com`, and terminates every process it can signal otherwise.
# Upstream ADR 1751 says a hook is not a security control, that actions are
# downloaded before it runs and that a hook which cannot start only fails the
# job; it never replaces the broker rules.
#
# The one-JIT-per-start option is supported only by a reviewed mint tool that
# runs broker steps 2-6 off the console; in place of step 1 it checks that
# `GET /repos/project-alpha-rsps/server` returns ID `1207177553`. Pasting a JIT
# with no checks is not acceptable.
#
# No key is configured here. `shockstruck/nixos` is a public repository, so a
# broker key never goes into Git, the store, an image, the guest or logs. If a
# broker holds one, it is a host-only systemd encrypted credential at
# `/etc/credstore.encrypted/project-alpha-console-runner-app-key`, root-only,
# loaded only by the broker's own unit with `LoadCredentialEncrypted` and gated
# by `ConditionPathExists`, as `context-mesh-proxy.nix` does. This module
# declares no broker unit and no key option.
#
# The guest is a standalone minimal NixOS system evaluated from the pinned
# nixpkgs, never the workstation configuration, and only its own closure is
# packed into it. The root disk is a fresh ext4 image in the unit's state
# directory, recreated on every start and removed when the unit stops, so no
# guest state or runner work survives.
{ config
, lib
, pkgs
, ...
}:

let
  cfg = config.services.project-alpha-console-runner;

  fwCfgName = "opt/io.project-alpha-console-runner/jit";
  stateDir = "/var/lib/project-alpha-console-runner";

  guest = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    system = "x86_64-linux";
    specialArgs = { inherit fwCfgName; };
    modules = [ ./project-alpha-runner-guest.nix ];
  };

  guestToplevel = guest.config.system.build.toplevel;
  guestClosure = pkgs.closureInfo { rootPaths = [ guestToplevel ]; };

  # The helper `nixos/modules/virtualisation/qemu-vm.nix` uses to pack a store
  # closure into a read-only erofs image. Only the guest's own closure is
  # listed, so the host store is never exposed to the guest.
  packStoreImage = import (pkgs.path + "/nixos/lib/erofs-store-image.nix") {
    hostPkgs = pkgs;
    storePaths = "${guestClosure}/store-paths";
    label = "nix-store";
    destination = ''"$storeImage"'';
  };

  launcher = pkgs.writeShellApplication {
    name = "project-alpha-console-runner";
    runtimeInputs = with pkgs; [
      coreutils
      e2fsprogs
    ];
    text = ''
      credential="''${CREDENTIALS_DIRECTORY:?}/jit"

      # Fail closed before anything starts: both runtime inputs are external
      # and have no fallback. systemd connected the gateway socket as fd 3
      # (`OpenFile=`) and a missing socket fails the unit before this runs.
      if [ "''${LISTEN_FDS:-}" != "1" ] || ! [ -S /proc/self/fd/3 ]; then
        echo "egress gateway socket was not passed as a single working file descriptor" >&2
        exit 1
      fi
      unset LISTEN_FDS LISTEN_PID LISTEN_FDNAMES

      if ! [ -s "$credential" ]; then
        echo "JIT credential is missing or empty" >&2
        exit 1
      fi

      # A fresh writable root and a fresh read-only store, both per start.
      rm -f ${stateDir}/scratch.img ${stateDir}/store.img
      scratchImage=${stateDir}/scratch.img
      storeImage=${stateDir}/store.img
      truncate -s ${toString cfg.scratchDiskGiB}G "$scratchImage"
      mkfs.ext4 -q -F -L nixos-root "$scratchImage"

      ${packStoreImage}

      exec ${pkgs.qemu_kvm}/bin/qemu-system-x86_64 \
        -name project-alpha-console-runner \
        -machine q35 -accel kvm -cpu host \
        -smp ${toString cfg.vcpus} -m ${toString cfg.memoryMiB} \
        -nodefaults -no-user-config \
        -sandbox on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny \
        -display none -monitor none -serial stdio \
        -kernel ${guestToplevel}/kernel \
        -initrd ${guestToplevel}/initrd \
        -append "$(cat ${guestToplevel}/kernel-params) init=${guestToplevel}/init console=ttyS0,115200n8" \
        -fw_cfg "name=${fwCfgName},file=$credential" \
        -netdev "stream,id=net0,addr.type=fd,addr.str=3" \
        -device virtio-net-pci,netdev=net0 \
        -drive "file=$scratchImage,if=virtio,format=raw,cache=writeback,werror=report" \
        -drive "file=$storeImage,if=virtio,format=raw,readonly=on,cache=none" \
        -no-reboot
    '';
  };
in
{
  options.services.project-alpha-console-runner = {
    enable = lib.mkEnableOption "the Project Alpha console CI runner, one disposable KVM guest per manual start";

    egressSocket = lib.mkOption {
      # `OpenFile=` splits on `:` and expands `%`, so the path admits neither.
      type = lib.types.strMatching "/[A-Za-z0-9._/-]+";
      description = ''
        Absolute path of the AF_UNIX stream socket served by the isolated
        egress gateway. systemd connects it (`OpenFile=`) and passes it to the
        launcher as file descriptor 3, so the socket can be root-only and a
        missing socket fails the unit. QEMU's only NIC is a `-netdev stream`
        over that descriptor; the gateway must carry framed Ethernet, supply
        guest addressing and deny host, LAN, control-plane and metadata
        destinations outside the VM. This module does not provision or
        authorize the gateway.
      '';
    };

    jitSocket = lib.mkOption {
      # `LoadCredential=` splits on `:` and expands `%`, so the path admits
      # neither.
      type = lib.types.strMatching "/[A-Za-z0-9._/-]+";
      description = ''
        Absolute path of the root-provisioned AF_UNIX stream socket that yields
        one fresh, single-use GitHub encoded JIT configuration for a
        repository-level runner on `project-alpha-rsps/server` only, read once
        through systemd `LoadCredential=`. The broker must authenticate its
        caller and follow these rules:

        1. Request a token for repository ID `1207177553` with
           `administration: write`; the response must show
           `repository_selection` = `selected`, exactly that one repository
           with full name `project-alpha-rsps/server`, and permissions exactly
           `administration: write` and `metadata: read`.
        2. POST the constant
           `/repos/project-alpha-rsps/server/actions/runners/generate-jitconfig`
           path on `api.github.com` with redirects off and a fresh random
           runner name; accept only 201.
        3. Prove the repository with GET on
           `/repos/project-alpha-rsps/server/actions/runners/{runner.id}` using
           the same token and redirects off; require 200 and the same `id`,
           `name` and label names.
        4. Require label names exactly `["project-alpha-rsps-console"]` and no
           default labels; `runner_group_id` is the default group's integer,
           confirmed before activation and not recorded here. The step 2 value
           must equal that integer; only when step 2 omits it is step 3's value
           compared, and absence from both is a rejection. Require `ephemeral`
           `true` when present.
        5. Require decoded `AgentName` (key matched ignoring case) to equal the
           random name exactly; never compare `runner.id` with `AgentId`, then
           apply the guest rules.
        6. On any failure, timeout or odd response send zero bytes on the
           socket (the launcher rejects an empty credential), DELETE the
           runner, and log a fixed message only. If the ID is unknown, find the
           runner by its exact random name. Refuse further mints until a
           person confirms the runner list.

        The guest applies defence in depth: `gitHubUrl` may be absent but must
        match `https://github.com/project-alpha-rsps/server` exactly when
        present, at least one of `serverUrl` and `serverUrlV2` must be present
        and each one present must match a `*.actions.githubusercontent.com`
        service host, and a job-started hook requires
        `GITHUB_REPOSITORY_ID` `1207177553` and `GITHUB_SERVER_URL`
        `https://github.com`. That hook is not a security control: upstream ADR
        1751 notes actions download before it runs and a hook that cannot
        start only fails the job, so it never replaces the broker checks. The
        one-JIT-per-start option needs a reviewed mint tool that runs steps 2-6
        off the console and, in place of step 1, checks that
        `GET /repos/project-alpha-rsps/server` returns ID `1207177553`;
        pasting an unchecked JIT is not acceptable. The broker declares no
        organization runner group and applies no workflow/ref allowlist. No App
        key, installation token or generic registration token is configured
        here.
      '';
    };

    vcpus = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "Guest vCPUs passed to QEMU with `-smp`.";
    };

    memoryMiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8192;
      description = "Guest RAM in MiB passed to QEMU with `-m`.";
    };

    scratchDiskGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 24;
      description = ''
        Size of the freshly formatted ext4 guest root disk. It is a sparse file
        in the unit's state directory and is removed when the unit stops.
      '';
    };

    cpuQuota = lib.mkOption {
      type = lib.types.str;
      default = "400%";
      description = "systemd `CPUQuota=` for the launcher's cgroup.";
    };

    memoryMax = lib.mkOption {
      type = lib.types.str;
      default = "12G";
      description = ''
        systemd `MemoryMax=` for the launcher's cgroup. Leave room above
        `memoryMiB` for QEMU's own overhead.
      '';
    };

    memorySwapMax = lib.mkOption {
      type = lib.types.str;
      default = "0";
      description = "systemd `MemorySwapMax=` for the launcher's cgroup.";
    };

    runtimeMaxSec = lib.mkOption {
      type = lib.types.str;
      default = "06:00:00";
      description = ''
        systemd `RuntimeMaxSec=`: the backstop that stops a guest whose runner
        never terminates.
      '';
    };

    stopTimeoutSec = lib.mkOption {
      type = lib.types.str;
      default = "60s";
      description = "systemd `TimeoutStopSec=` for the launcher.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.kvm = { };

    users.groups.project-alpha-console-runner = { };
    users.users.project-alpha-console-runner = {
      isSystemUser = true;
      group = "project-alpha-console-runner";
      home = stateDir;
      createHome = false;
      shell = pkgs.bashInteractive;
    };

    systemd.services.project-alpha-console-runner = {
      description = "Project Alpha console CI runner (one disposable KVM guest)";

      # Manual only: there is no `wantedBy`, and the unit is stopped before the
      # host sleeps or shuts down.
      before = [ "sleep.target" ];
      conflicts = [ "sleep.target" ];
      requires = [ "project-alpha-egress.socket" ];
      after = [ "project-alpha-egress.socket" ];

      serviceConfig = {
        Type = "exec";
        User = "project-alpha-console-runner";
        Group = "project-alpha-console-runner";
        SupplementaryGroups = [ "kvm" ];

        StateDirectory = "project-alpha-console-runner";
        StateDirectoryMode = "0700";

        # `/run` and `/var` are empty read-only tmpfs inside the unit: the
        # host's systemd, D-Bus, Docker and user sockets and the credential
        # key are not reachable from QEMU. Only the state directory is bound
        # back, writable.
        TemporaryFileSystem = [ "/run:ro" "/var:ro" ];
        BindPaths = [ stateDir ];
        ReadWritePaths = [ stateDir ];

        ExecStart = "${launcher}/bin/project-alpha-console-runner";
        # One command string: systemd renders each list item as its own
        # ExecStopPost directive, so a split argv would not run.
        ExecStopPost = [
          "${pkgs.coreutils}/bin/rm -f ${stateDir}/scratch.img ${stateDir}/store.img"
        ];

        # One fresh JIT configuration, read from the broker's socket by the
        # service manager before exec, and the egress gateway socket connected
        # by the service manager and passed as fd 3. Both happen outside the
        # unit's mount namespace and system-call filters.
        LoadCredential = [ "jit:${cfg.jitSocket}" ];
        OpenFile = [ "${cfg.egressSocket}:egress" ];

        Restart = "no";
        TimeoutStartSec = "5min";
        TimeoutStopSec = cfg.stopTimeoutSec;
        RuntimeMaxSec = cfg.runtimeMaxSec;
        CPUQuota = cfg.cpuQuota;
        MemoryMax = cfg.memoryMax;
        MemorySwapMax = cfg.memorySwapMax;

        UMask = "0077";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        PrivateTmp = true;
        RemoveIPC = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        CapabilityBoundingSet = [ "" ];
        AmbientCapabilities = [ ];

        # The guest's only network path is the inherited gateway descriptor.
        # The unit runs in an empty network namespace and may create no socket
        # at all; QEMU's own sandbox, the mount hiding above and the filters
        # below are the further layers.
        PrivateNetwork = true;
        RestrictAddressFamilies = [ "none" ];
        InaccessiblePaths = [
          "-/nix/var"
          "-${cfg.jitSocket}"
          "-${cfg.egressSocket}"
          "-/etc/credstore"
          "-/etc/credstore.encrypted"
        ];

        # `@system-service` omits `seccomp`, which QEMU's `-sandbox` needs, and
        # reaches io_uring through `@aio`; io_uring can open sockets without
        # `socket(2)` and QEMU 11.1.2 falls back to aio silently when it is
        # denied.
        SystemCallArchitectures = "native";
        SystemCallErrorNumber = "EPERM";
        SystemCallFilter = [
          "@system-service"
          "seccomp"
          "~@privileged @resources"
          "~socket socketpair connect bind listen accept accept4"
          "~io_uring_setup io_uring_enter io_uring_register"
        ];

        # `/dev/kvm` is the only device. `PrivateDevices=yes` would hide it:
        # systemd's private /dev clones a fixed pseudo-device list only.
        DevicePolicy = "closed";
        DeviceAllow = [ "/dev/kvm rw" ];
      };
    };
  };
}
