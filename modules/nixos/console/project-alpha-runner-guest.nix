# Guest half of `project-alpha-runner.nix`: a standalone minimal x86_64 NixOS
# system that the console's launcher boots directly with QEMU/KVM. It is never
# part of a host's module list; only `./project-alpha-runner.nix` evaluates it.
#
# The guest owns one job and one job only. It boots from a freshly formatted
# ext4 root on the first virtio disk and a read-only EROFS store image on the
# second, has no host share, container socket or Nix daemon socket, and no
# device but its own virtual ones. The single-use JIT configuration arrives
# through QEMU fw_cfg at `opt/io.project-alpha-console-runner/jit`; Linux exposes
# that blob as a root-only `raw` sysfs attribute
# (`drivers/firmware/qemu_fw_cfg.c`: `S_IRUSR`). The root bootstrap runs
# `project-alpha-jit-state.sh`, which reads `.runner` the way Newtonsoft does
# (case-insensitive keys), requires an ephemeral runner with a non-empty work
# folder, allows `gitHubUrl` to be absent but requires an exact match when it is
# present, and requires at least one `serverUrl`/`serverUrlV2` to be present
# with each one present matching a `*.actions.githubusercontent.com` service
# host. It materialises only the pinned runner's own state files
# under the guest-local `RUNNER_ROOT` — nothing is written until every value
# has validated — deletes the payload, and starts `Runner.Listener` without the
# blob in its argv or environment.
#
# Before any job step runs, the runner starts the embedded job-started hook
# (`ACTIONS_RUNNER_HOOK_JOB_STARTED`), which requires `GITHUB_REPOSITORY_ID` of
# `1207177553` and `GITHUB_SERVER_URL` of `https://github.com` from the runner's
# own context and otherwise terminates every process it can signal. Upstream
# ADR 1751 says such a hook is not a security control, that actions are
# downloaded before it runs and that a hook which cannot start only fails the
# job; it never replaces the broker checks. The runner picks `bash` (else `sh`)
# from the listener's `PATH` to run a `.sh` hook, and the pinned
# `systemd.defaultPath` has neither, so the bootstrap's `runtimeInputs` carries
# `pkgs.bash`.
{ config
, modulesPath
, pkgs
, fwCfgName
, ...
}:

let
  runnerUser = "project-alpha-runner";
  runnerHome = "/var/lib/project-alpha-runner";
  runnerRoot = "${runnerHome}/.github-runner";
  expectedGitHubUrl = "https://github.com/project-alpha-rsps/server";

  # The decoder is a committed fragment so it can be read and tested on its
  # own. `writeShellApplication` prepends its shebang and `set` options; the
  # file starts with a shellcheck directive instead.
  jitState = pkgs.writeShellApplication {
    name = "project-alpha-jit-state";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = builtins.readFile ./project-alpha-jit-state.sh;
  };

  # The runner runs a `.sh` job-started hook with `bash` (else `sh`) from its
  # own `PATH`; the file itself starts with a shellcheck directive, so
  # `writeShellApplication` supplies the shebang and `set` options.
  jobStartedHook = pkgs.writeShellApplication {
    name = "project-alpha-job-started.sh";
    runtimeInputs = [ ];
    text = builtins.readFile ./project-alpha-job-started.sh;
  };

  bootstrap = pkgs.writeShellApplication {
    name = "project-alpha-runner-bootstrap";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.kmod
      pkgs.util-linux
    ];
    text = ''
      fwCfgPath="/sys/firmware/qemu_fw_cfg/by_name/${fwCfgName}/raw"

      modprobe -q qemu_fw_cfg || true
      if ! [ -e "$fwCfgPath" ]; then
        echo "QEMU fw_cfg credential is unavailable" >&2
        exit 1
      fi

      payload="$(mktemp /run/project-alpha-jit.XXXXXXXXXX)"
      trap 'rm -f "$payload"' EXIT
      cat "$fwCfgPath" > "$payload"
      if ! [ -s "$payload" ]; then
        echo "JIT payload is empty" >&2
        exit 1
      fi

      install -d -m 0700 -o ${runnerUser} -g ${runnerUser} ${runnerRoot}
      TMPDIR=/run ${jitState}/bin/project-alpha-jit-state \
        "$payload" ${runnerRoot} ${runnerUser} "${expectedGitHubUrl}"
      rm -f "$payload"
      trap - EXIT

      # The listener reads .runner/.credentials from RUNNER_ROOT. The raw blob
      # is gone before it starts and never reaches argv or the environment. The
      # job-started hook is a store path, not a credential, and needs `bash` on
      # the listener's PATH to start.
      exec ${pkgs.util-linux}/bin/runuser -u ${runnerUser} -- \
        ${pkgs.coreutils}/bin/env \
        HOME=${runnerHome} \
        RUNNER_ROOT=${runnerRoot} \
        ACTIONS_RUNNER_HOOK_JOB_STARTED=${jobStartedHook}/bin/project-alpha-job-started.sh \
        ${pkgs.github-runner}/bin/Runner.Listener run --once
    '';
  };
in
{
  imports = [ (modulesPath + "/profiles/minimal.nix") ];

  system.stateVersion = "26.05";

  boot.loader.grub.enable = false;

  # nixpkgs' kernel config builds filesystems and QEMU's fw_cfg sysfs support as
  # modules on x86_64, so the initrd carries the ones the store mount needs.
  boot.initrd.availableKernelModules = [
    "erofs"
    "virtio_blk"
    "virtio_pci"
  ];
  boot.initrd.kernelModules = [ "erofs" ];
  boot.kernelModules = [ "qemu_fw_cfg" ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos-root";
    fsType = "ext4";
  };
  fileSystems."/nix/.ro-store" = {
    device = "/dev/disk/by-label/nix-store";
    fsType = "erofs";
    neededForBoot = true;
    options = [ "ro" ];
  };
  fileSystems."/nix/store" = {
    device = "/nix/.ro-store";
    fsType = "none";
    options = [ "bind" ];
  };

  networking.hostName = "project-alpha-console-runner";
  networking.useDHCP = true;
  networking.usePredictableInterfaceNames = false;

  # Time comes from KVM and the gateway offers no NTP route.
  services.timesyncd.enable = false;
  services.openssh.enable = false;

  # The runner works as its own unprivileged user; sudo exists nowhere, and the
  # guest exposes no Nix daemon socket to a job either.
  security.sudo.enable = false;
  nix.daemon.enable = false;

  environment.systemPackages = with pkgs; [
    bashInteractive
    cacert
    coreutils
    curl
    diffutils
    findutils
    gawk
    git
    gnugrep
    gnused
    gnutar
    gzip
    jdk21
    jq
    procps
    unzip
    which
    xz
  ];

  systemd.tmpfiles.rules = [
    "d ${runnerHome} 0700 ${runnerUser} ${runnerUser} -"
  ];

  users.groups.${runnerUser} = { };
  users.users.${runnerUser} = {
    isSystemUser = true;
    group = runnerUser;
    home = runnerHome;
    createHome = false;
    shell = pkgs.bashInteractive;
  };

  systemd.services.project-alpha-runner = {
    description = "Run one Project Alpha CI job and shut the VM down";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "systemd-modules-load.service"
    ];

    serviceConfig = {
      Type = "exec";
      ExecStart = "${bootstrap}/bin/project-alpha-runner-bootstrap";
      # The listener is single-use. Whatever its exit status, the guest must not
      # outlive it; this also covers a bootstrap that fails before the listener
      # starts.
      # One command string: systemd renders each list item as its own
      # ExecStopPost directive, so a split argv would not run.
      ExecStopPost = [
        "${config.systemd.package}/bin/systemctl poweroff --no-block"
      ];
      Restart = "no";
      TimeoutStartSec = "2min";
      TimeoutStopSec = "30s";
      KillMode = "control-group";
    };
  };
}
