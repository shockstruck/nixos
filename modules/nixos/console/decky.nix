# Decky Loader (packages/decky-loader.nix) + the Unifideck plugin
# (packages/unifideck.nix), console-only.
#
# Runs as root: as of decky-loader 3.2.8 this is required even when no
# plugin needs root, because the loader itself setuid's to the unprivileged
# user per plugin (SteamDeckHomebrew/decky-loader issue 446,
# backend/decky_loader/plugin/sandboxed_plugin.py).
#
# The unprivileged user is the console's Steam user (`config.myusers`'
# head), not a separate `decky` account (Jovian-NixOS's default): Unifideck's
# Steam-shortcut launcher runs as the Steam user and reads
# `~/.local/share/unifideck/…`, so a plugin running as any other user cannot
# see its own state.
#
# `systemd.tmpfiles.settings` links Unifideck into `plugins/` as a store
# symlink (`L+`) rather than copying it in: that keeps the plugin
# declarative and rebuild-reproducible, at the cost of decky-loader's own
# in-UI updater refusing to touch it (it can't write through a symlink into
# the store) — updates to Unifideck are a version bump in
# packages/unifideck.nix instead. `plugins/` itself stays a regular,
# user-writable directory (not tmpfiles-managed as a whole) so decky-loader
# can still install/manage any other plugin through its own UI.
#
# `programs.nix-ld` is enabled because Unifideck vendors two prebuilt glibc
# ELF binaries (`nile`, `comet`) under its `bin/` that are not built against
# the Nix store's dynamic linker.
{ config
, pkgs
, ...
}:
let
  user = builtins.head config.myusers;
  stateDir = "/var/lib/decky-loader";
  deckyLoader = pkgs.callPackage ../../../packages/decky-loader.nix { };
  unifideck = pkgs.callPackage ../../../packages/unifideck.nix { };
in
{
  systemd.services.decky-loader = {
    description = "Steam Deck Plugin Loader";

    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    environment = {
      UNPRIVILEGED_USER = user;
      UNPRIVILEGED_PATH = stateDir;
      PLUGIN_PATH = "${stateDir}/plugins";
    };

    path = with pkgs; [
      python3
      bash
      coreutils
      psmisc
      procps
      systemd
      curl
      gnutar
      gzip
    ];

    preStart = ''
      mkdir -p "${stateDir}" "${stateDir}/plugins" "${stateDir}/settings" "${stateDir}/data" "${stateDir}/logs"
      chown "${user}:" "${stateDir}" "${stateDir}/plugins"
      chown -R "${user}:" "${stateDir}/settings" "${stateDir}/data" "${stateDir}/logs"
    '';

    serviceConfig = {
      ExecStart = "${deckyLoader}/bin/decky-loader";
      KillMode = "process";
      TimeoutStopSec = 45;
    };
  };

  systemd.tmpfiles.settings."10-decky-plugins" = {
    "${stateDir}/plugins/Unifideck"."L+".argument = "${unifideck}";
  };

  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      openssl
    ];
  };
}
