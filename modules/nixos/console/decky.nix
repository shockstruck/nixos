# Decky Loader (packages/decky-loader.nix), console-only.
#
# Runs as root: as of decky-loader 3.2.8 this is required even when no
# plugin needs root, because the loader itself setuid's to the unprivileged
# user per plugin (SteamDeckHomebrew/decky-loader issue 446,
# backend/decky_loader/plugin/sandboxed_plugin.py).
#
# The unprivileged user is the console's Steam user (`config.myusers`'
# head), not a separate `decky` account (Jovian-NixOS's default): plugins
# that shell out to Steam (e.g. writing Steam shortcuts) expect to run as
# the same user Steam itself runs as.
{ config
, pkgs
, ...
}:
let
  user = builtins.head config.myusers;
  stateDir = "/var/lib/decky-loader";
  deckyLoader = pkgs.callPackage ../../../packages/decky-loader.nix { };
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
}
