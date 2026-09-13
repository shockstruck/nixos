# The console's Home Manager profile. A subdirectory without default.nix is
# ignored both by nixos-unified autowiring and by the myusers default (which
# only readDir's regular *.nix files directly under configurations/home,
# verified in nixos-unified's nix/modules/flake-parts/autowire.nix) — so this
# tree needs no default.nix and reaches neither desktop nor laptop's myusers
# list. modules/nixos/common/myusers.nix's myhome.dir option is what points
# the console host's home-manager.users import here instead of the shared
# configurations/home/kevin.nix.
{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    self.homeModules.me
    self.homeModules.nix
    self.homeModules.gc
    self.homeModules.git
    self.homeModules.ssh
  ];

  me = {
    username = "kevin";
    fullname = "shockstruck";
    email = "186360364+shockstruck@users.noreply.github.com";
  };

  home.stateVersion = "26.05";
}
