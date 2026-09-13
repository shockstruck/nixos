# The console's Home Manager profile. A subdirectory without default.nix is
# ignored both by nixos-unified autowiring and by the myusers default (which
# only readDir's regular *.nix files directly under configurations/home,
# verified in nixos-unified's nix/modules/flake-parts/autowire.nix) — so this
# tree needs no default.nix and reaches neither desktop nor laptop's myusers
# list. modules/nixos/common/myusers.nix's myhome.dir option is what points
# the console host's home-manager.users import here instead of the shared
# configurations/home/kevin.nix.
#
# theme/hyprland/noctalia/kitty back the Hyprland/Noctalia desktop session
# from modules/nixos/console/desktop.nix (console-session's "Switch to
# Desktop" target). Not idle: stasis would lock/suspend the console desktop,
# and couch use has no keyboard at hand to clear the lock prompt. Not
# packages/shell/brave/bitwarden either — those are desktop/laptop's
# day-to-day app set, not needed for the occasional shortcut-adding session
# this profile exists for.
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
    self.homeModules.theme
    self.homeModules.hyprland
    self.homeModules.noctalia
    self.homeModules.kitty
  ];

  me = {
    username = "kevin";
    fullname = "shockstruck";
    email = "186360364+shockstruck@users.noreply.github.com";
  };

  home.stateVersion = "26.05";
}
