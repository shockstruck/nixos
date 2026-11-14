# Bazaar is for trialling flatpak apps before they are added declaratively.
# It has no remote list of its own — it shows whatever flatpak remotes the
# system already has — so Flathub and Flathub Beta are registered here as
# system remotes for it to see. `services.flatpak.enable` is not set here:
# it is already on for every host that imports this file (gui/hyprland.nix
# and console/session.nix each set it), so the grayjay-flatpak and
# chromium-flatpak oneshots' own `remote-add --if-not-exists flathub` stays
# idempotent against the flathub remote this oneshot also adds.
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.bazaar ];

  systemd.services.flatpak-remotes = {
    description = "Register Flathub and Flathub Beta as system flatpak remotes";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      ${pkgs.flatpak}/bin/flatpak remote-add --system --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
      ${pkgs.flatpak}/bin/flatpak remote-add --system --if-not-exists flathub-beta \
        https://flathub.org/beta-repo/flathub-beta.flatpakrepo
    '';
  };
}
