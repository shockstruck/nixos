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
# authenticate its caller and use a token scoped to `project-alpha-rsps/server`
# only; it registers the runner with the exact `project-alpha-rsps-console`
# label and no default labels, uses the default group's integer
# `runner_group_id` (confirmed before activation, not recorded here), declares
# no organization runner group and applies no workflow/ref allowlist. It must
# check the returned runner ID, labels and repository, and on any mismatch
# delete the runner and discard the JIT.
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
        caller and use a token scoped to that repository; it registers the
        runner with the exact `project-alpha-rsps-console` label and no default
        labels, uses the default group's integer `runner_group_id` (confirmed
        before activation, not recorded here), declares no organization runner
        group and applies no workflow/ref allowlist. It must check the returned
        runner ID, labels and repository, and on any mismatch delete the runner
        and discard the JIT. No App key, installation token or generic
        registration token is configured here.
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
