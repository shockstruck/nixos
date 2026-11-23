# Project Alpha CI runner for the console: one disposable KVM guest per
# explicit start. Console-only and disabled by default, so with `enable =
# false` nothing here is instantiated — no user, no unit, no guest evaluation —
# and the console starts no runner and needs no credential.
#
# Enabling it needs two runtime interfaces this module does not provision:
#
#   * `egressSocket`: an AF_UNIX stream socket served by the separately
#     reviewed isolated egress gateway. It is QEMU's only network path
#     (`-netdev stream`): the gateway carries framed Ethernet, supplies guest
#     addressing and enforces destinations outside the VM. There is no bridge,
#     no SLiRP, no host mount and no forwarded port.
#   * `jitSocket`: a root-provisioned AF_UNIX stream socket that yields one
#     fresh, single-use GitHub encoded JIT configuration. systemd reads it with
#     `LoadCredential=` before exec (systemd.exec: an absolute path that
#     refers to an AF_UNIX stream socket is read once at process invocation).
#     QEMU hands the credential to the guest through fw_cfg by file path only,
#     never by value on the host command line, and the guest bootstrap feeds it
#     to `Runner.Listener` once.
#
# The guest is a standalone minimal NixOS system evaluated from the pinned
# nixpkgs, never the workstation configuration, and only its own closure is
# packed into it. The root disk is a fresh ext4 image in the unit's state
# directory, recreated on every start and removed when the unit stops, so no
# guest state or runner work survives.
{
  config,
  lib,
  pkgs,
  ...
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
      egressSocket=${lib.escapeShellArg cfg.egressSocket}
      credential="''${CREDENTIALS_DIRECTORY:?}/jit"

      # Fail closed before anything starts: both runtime inputs are external
      # and have no fallback.
      if ! [ -S "$egressSocket" ]; then
        echo "egress gateway socket is missing: $egressSocket" >&2
        exit 1
      fi
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
        -display none -monitor none -serial stdio \
        -kernel ${guestToplevel}/kernel \
        -initrd ${guestToplevel}/initrd \
        -append "$(cat ${guestToplevel}/kernel-params) init=${guestToplevel}/init console=ttyS0,115200n8" \
        -fw_cfg "name=${fwCfgName},file=$credential" \
        -netdev "stream,id=net0,addr.type=unix,addr.path=$egressSocket" \
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
      type = lib.types.strMatching "/.*";
      description = ''
        Absolute path of the AF_UNIX stream socket served by the isolated
        egress gateway. QEMU's only NIC is a `-netdev stream` over this socket;
        the gateway must carry framed Ethernet, supply guest addressing and
        deny host, LAN, control-plane and metadata destinations outside the VM.
        This module does not provision or authorize the gateway.
      '';
    };

    jitSocket = lib.mkOption {
      type = lib.types.strMatching "/.*";
      description = ''
        Absolute path of the root-provisioned AF_UNIX stream socket that yields
        one fresh, single-use GitHub encoded JIT configuration, read once through
        systemd `LoadCredential=`. The broker owns its expiry, policy and
        one-use enforcement; no group ID, App key, installation token or generic
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
        ReadWritePaths = [ stateDir ];

        ExecStart = "${launcher}/bin/project-alpha-console-runner";
        ExecStopPost = [
          "${pkgs.coreutils}/bin/rm"
          "-f"
          "${stateDir}/scratch.img"
          "${stateDir}/store.img"
        ];

        # One fresh JIT configuration, read from the broker's socket by the
        # service manager before exec.
        LoadCredential = [ "jit:${cfg.jitSocket}" ];

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

        # The guest's only network path is the gateway socket. QEMU runs in an
        # empty network namespace and may create AF_UNIX sockets only.
        PrivateNetwork = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];

        # `/dev/kvm` is the only device. `PrivateDevices=yes` would hide it:
        # systemd's private /dev clones a fixed pseudo-device list only.
        DevicePolicy = "closed";
        DeviceAllow = [ "/dev/kvm rw" ];
      };
    };
  };
}
