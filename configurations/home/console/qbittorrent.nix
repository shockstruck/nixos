# Headless qBittorrent for OpenGameInstaller (OGI), which drives a qBittorrent
# WebUI as its torrent client (defaults http://127.0.0.1:8080, user `admin`).
# Runs as a Home Manager user service rather than nixpkgs' services.qbittorrent
# because that module hardcodes ProtectHome="yes" and PrivateUsers=true
# (nixos/modules/services/torrent/qbittorrent.nix), while OGI passes its own
# savepath under /home/kevin/UGI_Games when it adds a torrent, so qBittorrent
# has to run as kevin and write inside home.
#
# No credential lives in the source: `WebUI\LocalHostAuth=false` makes
# qBittorrent start a session for loopback clients without checking a
# password, which still satisfies OGI's client (it needs the login response's
# Set-Cookie), so whatever username and password OGI's form holds will work.
# The WebUI is bound to 127.0.0.1 only and no firewall setting changes.
#
# The config is copied in on every start (as nixpkgs' module does), never
# symlinked: qBittorrent rewrites qBittorrent.conf, and a store symlink would
# make that a write error. WebUI preferences changed at runtime therefore do
# not survive a restart.
{ pkgs, ... }:
let
  # Written with a literal backslash in the key names: qBittorrent's INI uses
  # `\` as its section separator inside Preferences.
  configFile = pkgs.writeText "qBittorrent.conf" ''
    [LegalNotice]
    Accepted=true

    [Preferences]
    WebUI\Address=127.0.0.1
    WebUI\Enabled=true
    WebUI\LocalHostAuth=false
    WebUI\Port=8080
  '';
  profileDir = "%h/.local/share/qbittorrent-nox";
in
{
  systemd.user.services.qbittorrent-nox = {
    Unit.Description = "qBittorrent-nox (WebUI for OpenGameInstaller)";

    Install.WantedBy = [ "default.target" ];

    Service = {
      ExecStartPre = "${pkgs.coreutils}/bin/install -Dm600 ${configFile} ${profileDir}/qBittorrent/config/qBittorrent.conf";
      ExecStart = "${pkgs.qbittorrent-nox}/bin/qbittorrent-nox --profile=${profileDir} --confirm-legal-notice";
      Restart = "on-failure";
    };
  };
}
