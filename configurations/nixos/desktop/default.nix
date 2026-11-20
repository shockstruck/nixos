{ flake, ... }:

let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    self.nixosModules.default
    self.nixosModules.gui
    inputs.disko.nixosModules.disko
    ./boot.nix
    ./hardware.nix
    ./graphics.nix
    ./power.nix
    ./storage.nix
    ./virtualisation.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "desktop";

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

  system.stateVersion = "24.11";
}
