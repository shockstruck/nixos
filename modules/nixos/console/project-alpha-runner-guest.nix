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
# (`drivers/firmware/qemu_fw_cfg.c`: `S_IRUSR`) and the bootstrap below reads it
# once, unlinks the temporary copy, and hands it to `Runner.Listener`.
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

      jitFile="$(mktemp /run/project-alpha-jit.XXXXXXXXXX)"
      trap 'rm -f "$jitFile"' EXIT
      cat "$fwCfgPath" > "$jitFile"
      if ! [ -s "$jitFile" ]; then
        echo "JIT configuration is empty" >&2
        exit 1
      fi
      jit="$(cat "$jitFile")"
      rm -f "$jitFile"
      trap - EXIT

      exec ${pkgs.util-linux}/bin/runuser -u ${runnerUser} -- \
        ${pkgs.coreutils}/bin/env \
        HOME=${runnerHome} \
        RUNNER_ROOT=${runnerRoot} \
        ${pkgs.github-runner}/bin/Runner.Listener run --once --jitconfig "$jit"
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

  # The runner works as its own unprivileged user; sudo exists nowhere.
  security.sudo.enable = false;

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
      ExecStopPost = [
        "${config.systemd.package}/bin/systemctl"
        "poweroff"
        "--no-block"
      ];
      Restart = "no";
      TimeoutStartSec = "2min";
      TimeoutStopSec = "30s";
      KillMode = "control-group";
    };
  };
}
