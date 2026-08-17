{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    self.homeModules.default
  ];

  # Defined by /modules/home/me.nix
  # And used all around in /modules/home/*
  me = {
    username = "kevin";
    fullname = "Kevin";
    email = "186360364+shockstruck@users.noreply.github.com";
  };

  # Compatibility baseline, not the installed Home Manager version.
  home.stateVersion = "26.05";
}
