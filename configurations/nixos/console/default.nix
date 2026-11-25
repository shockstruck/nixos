# The console is a hardware variant of the desktop (same AMD CPU/GPU, single
# NVMe, LUKS2/TPM2 disko layout), so its boot, hardware, power and storage
# truth is imported by path from ../desktop/ rather than copied. A console on
# different hardware would replace those four imports with local files.
{ flake, ... }:

let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    self.nixosModules.default
    self.nixosModules.console
    # Console-only and disabled by default; a path import keeps it out of the
    # shared `nixosModules.console` import list.
    ../../../modules/nixos/console/project-alpha-runner.nix
    inputs.disko.nixosModules.disko
    ../desktop/boot.nix
    ../desktop/hardware.nix
    ../desktop/power.nix
    ../desktop/storage.nix
    ./graphics.nix
  ];

  myhome.dir = self + /configurations/home/console;

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "console";

  # Pull signed outputs from the private Attic cache as well as upstream.
  # `extra-` appends to nixpkgs' substituter and trusted-key lists, and
  # signature verification stays on. The daemon reads its pull-only credential
  # from a root-owned netrc outside the store; that file is provisioned on the
  # host and is not declared here.
  nix.settings = {
    extra-substituters = [ "https://attic.panic.ac/nixos" ];
    extra-trusted-public-keys = [
      "nixos:hYos3dzj3xie6Zp6JKXVdujOaUO1UL2b6SxY0NjOaLw="
    ];
    netrc-file = "/etc/nix/attic.netrc";
  };

  services.project-alpha-console-runner = {
    enable = true;
    egressSocket = "/nonexistent/project-alpha-egress.sock";
    jitSocket = "/nonexistent/project-alpha-jit.sock";
  };

  # New host, first installed on this channel — deliberately not the
  # desktop/laptop's "24.11".
  system.stateVersion = "26.05";
}
