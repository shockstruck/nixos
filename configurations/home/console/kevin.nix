# The console's Home Manager profile. A subdirectory without default.nix is
# ignored both by nixos-unified autowiring and by the myusers default (which
# only readDir's regular *.nix files directly under configurations/home,
# verified in nixos-unified's nix/modules/flake-parts/autowire.nix) — so this
# tree needs no default.nix and reaches neither desktop nor laptop's myusers
# list. modules/nixos/common/myusers.nix's myhome.dir option is what points
# the console host's home-manager.users import here instead of the shared
# configurations/home/kevin.nix.
#
# theme/niri/noctalia/kitty back the niri/Noctalia desktop session
# from modules/nixos/console/desktop.nix (console-session's "Switch to
# Desktop" target). brave carries Kevin's "basic apps" ask for that session —
# same brave-origin module + Bitwarden extension as desktop/laptop, paired
# with the managed policy imported by modules/nixos/console/desktop.nix. Not
# idle: Noctalia's idle behaviours (modules/home/idle.nix) would lock/suspend
# the console desktop, and couch use has no keyboard at hand to clear the
# lock prompt. shell/neovim/direnv/nix-index are
# imported so the console's interactive shell (zsh + powerlevel10k) matches
# desktop/laptop. Still not packages/bitwarden — those are desktop/laptop's
# day-to-day app set, not needed for the occasional shortcut-adding session
# this profile exists for. nautilus is the
# one item lifted out of packages: the shared Noctalia dock pins
# org.gnome.Nautilus (modules/home/noctalia.nix) and the shortcut-adding
# sessions need a file manager to find the installed game; gvfs/udisks2 for
# it are enabled in modules/nixos/console/desktop.nix. heroic.nix asserts
# Heroic's auto-add-to-Steam toggle for the shortcut-adding sessions this
# profile exists for. archives is imported explicitly (this profile has no
# default.nix, so it misses modules/home/default.nix's readDir autowiring)
# so the same Nautilus double-click auto-extract this Nautilus reaches for
# shortcut-adding also works on this session. limo.nix installs Limo as this
# session's Nexus Mods client and makes it the default nxm:// handler, so
# Nexus's "Mod Manager Download" links deploy mods into the game directory
# from here for both Steam and OGI/Heroic shortcuts; opening it through its
# `limo` wrapper first runs `limo-sync`, which registers the installed Steam
# and OGI games Limo does not manage yet. qbittorrent.nix runs headless
# qBittorrent-nox as a user service, the torrent client OGI's WebUI
# integration talks to over loopback.
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
    self.homeModules.niri
    self.homeModules.noctalia
    self.homeModules.kitty
    self.homeModules.brave
    self.homeModules.shell
    self.homeModules.neovim
    self.homeModules.direnv
    self.homeModules.nix-index
    self.homeModules.archives

    ./heroic.nix
    ./limo.nix
    ./qbittorrent.nix
  ];

  home.packages = [ pkgs.nautilus ];

  # Console-only: start OGI hidden at login so it's ready with a tray icon in
  # Noctalia's bar instead of showing a window. `extraConfig` is
  # `lib.types.lines` (nix-community/home-manager
  # modules/services/window-managers/niri.nix), so this concatenates with
  # modules/home/niri.nix's own `extraConfig` rather than overriding it;
  # desktop/laptop never import this file. niri runs `spawn-at-startup`
  # once when the session starts, not on config reload.
  wayland.windowManager.niri.extraConfig = ''
    spawn-at-startup "opengameinstaller" "--hidden"
  '';

  me = {
    username = "kevin";
    fullname = "shockstruck";
    email = "186360364+shockstruck@users.noreply.github.com";
  };

  home.stateVersion = "26.05";
}
