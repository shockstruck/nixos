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
# Desktop" target). brave carries Kevin's "basic apps" ask for that session —
# same brave-origin module + Bitwarden extension as desktop/laptop, paired
# with the managed policy imported by modules/nixos/console/desktop.nix. Not
# idle: hypridle would lock/suspend the console desktop, and couch use has no
# keyboard at hand to clear the lock prompt. shell/neovim/direnv/nix-index are
# imported so the console's interactive shell (zsh + powerlevel10k) matches
# desktop/laptop. Still not packages/bitwarden — those are desktop/laptop's
# day-to-day app set, not needed for the occasional shortcut-adding session
# this profile exists for. nautilus is the
# one item lifted out of packages: the shared Noctalia dock pins
# org.gnome.Nautilus (modules/home/noctalia.nix) and the shortcut-adding
# sessions need a file manager to find the installed game; gvfs/udisks2 for
# it are enabled in modules/nixos/console/desktop.nix. heroic.nix asserts
# Heroic's auto-add-to-Steam toggle for the shortcut-adding sessions this
# profile exists for. opengameinstaller.nix carries the Hyprland window rule
# that keeps OGI tiled instead of floating over the layout.
{ flake, pkgs, ... }:
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
    self.homeModules.brave
    self.homeModules.shell
    self.homeModules.neovim
    self.homeModules.direnv
    self.homeModules.nix-index

    ./heroic.nix
    ./opengameinstaller.nix
  ];

  home.packages = [ pkgs.nautilus ];

  me = {
    username = "kevin";
    fullname = "shockstruck";
    email = "186360364+shockstruck@users.noreply.github.com";
  };

  home.stateVersion = "26.05";
}
