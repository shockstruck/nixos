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
# (`drivers/firmware/qemu_fw_cfg.c`: `S_IRUSR`). The root bootstrap validates it,
# materialises only the pinned runner's own state files under the guest-local
# `RUNNER_ROOT`, deletes the payload, and starts `Runner.Listener` without the
# blob in its argv or environment.
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

  # Materialises the broker's encoded JIT payload as the pinned runner's own
  # state files. The outer payload is base64 of a JSON object that maps a config
  # file name to that file's base64 content; actions/runner's `Runner.cs` writes
  # each key under `RUNNER_ROOT`. Only the pinned runner's known config names are
  # accepted and `.runner` must declare itself ephemeral. No payload string is
  # used as a path, put in argv or logged.
  jitState = pkgs.writeShellApplication {
    name = "project-alpha-jit-state";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      payload="$1"
      runnerRoot="$2"
      stateDir="$(mktemp -d /run/project-alpha-jit.XXXXXXXXXX)"
      trap 'rm -rf "$stateDir"' EXIT

      if ! [ -s "$payload" ]; then
        echo "JIT payload is missing or empty" >&2
        exit 1
      fi
      if ! [ -d "$runnerRoot" ]; then
        echo "runner state directory is missing: $runnerRoot" >&2
        exit 1
      fi

      if ! base64 --decode "$payload" > "$stateDir/payload.json" 2>/dev/null; then
        echo "JIT payload is not valid base64" >&2
        exit 1
      fi
      if ! jq -e 'type == "object"' "$stateDir/payload.json" >/dev/null; then
        echo "JIT payload is not a JSON object" >&2
        exit 1
      fi

      unknown="$(jq -r --argjson allowed '[".runner",".credentials",".credentials_rsaparams"]' 'keys_unsorted - $allowed | .[]' "$stateDir/payload.json")"
      if [ -n "$unknown" ]; then
        echo "JIT payload names unsupported runner state: $unknown" >&2
        exit 1
      fi
      if ! jq -e 'has(".runner") and has(".credentials")' "$stateDir/payload.json" >/dev/null; then
        echo "JIT payload is missing .runner or .credentials" >&2
        exit 1
      fi

      if ! jq -r '.[".runner"]' "$stateDir/payload.json" | base64 --decode > "$stateDir/runner.json" 2>/dev/null; then
        echo "JIT .runner state is not valid base64" >&2
        exit 1
      fi
      if ! jq -e '(.ephemeral == true) and ((.workFolder // "") | length > 0)' "$stateDir/runner.json" >/dev/null; then
        echo "JIT .runner state is malformed or not ephemeral" >&2
        exit 1
      fi

      if ! jq -r '.[".credentials"]' "$stateDir/payload.json" | base64 --decode > "$stateDir/credentials" 2>/dev/null; then
        echo "JIT .credentials state is not valid base64" >&2
        exit 1
      fi
      if ! [ -s "$stateDir/credentials" ]; then
        echo "JIT .credentials state is empty" >&2
        exit 1
      fi
      if ! jq -e 'type == "object"' "$stateDir/credentials" >/dev/null; then
        echo "JIT .credentials state is not a JSON object" >&2
        exit 1
      fi

      haveRsaparams=0
      if jq -e 'has(".credentials_rsaparams")' "$stateDir/payload.json" >/dev/null; then
        if ! jq -r '.[".credentials_rsaparams"]' "$stateDir/payload.json" | base64 --decode > "$stateDir/rsaparams" 2>/dev/null; then
          echo "JIT .credentials_rsaparams state is not valid base64" >&2
          exit 1
        fi
        haveRsaparams=1
      fi

      # Nothing is written until every accepted state file has validated.
      rm -f "$runnerRoot/.runner" "$runnerRoot/.credentials" "$runnerRoot/.credentials_rsaparams"
      install -m 0600 -o ${runnerUser} -g ${runnerUser} "$stateDir/runner.json" "$runnerRoot/.runner"
      install -m 0600 -o ${runnerUser} -g ${runnerUser} "$stateDir/credentials" "$runnerRoot/.credentials"
      if [ "$haveRsaparams" = "1" ]; then
        install -m 0600 -o ${runnerUser} -g ${runnerUser} "$stateDir/rsaparams" "$runnerRoot/.credentials_rsaparams"
      fi
    '';
  };

  bootstrap = pkgs.writeShellApplication {
    name = "project-alpha-runner-bootstrap";
    runtimeInputs = [
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
      ${jitState}/bin/project-alpha-jit-state "$payload" ${runnerRoot}
      rm -f "$payload"
      trap - EXIT

      # The listener reads .runner/.credentials from RUNNER_ROOT. The raw blob
      # is gone before it starts and never reaches argv or the environment.
      exec ${pkgs.util-linux}/bin/runuser -u ${runnerUser} -- \
        ${pkgs.coreutils}/bin/env \
        HOME=${runnerHome} \
        RUNNER_ROOT=${runnerRoot} \
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
