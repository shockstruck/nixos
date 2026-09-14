{ config, ... }:
{
  # Nextcloud desktop sync client, started with the graphical session by
  # home-manager's services.nextcloud-client unit. That module only defines
  # the systemd user unit, so the package is added to home.packages
  # explicitly: that is what puts its .desktop entry, the
  # org.freedesktop.CloudProviders D-Bus activation file (Nautilus sidebar)
  # and share/nautilus-python/extensions/syncstate-Nextcloud.py (sync
  # emblems + context menu) in the profile. Nautilus runs that script via
  # nautilus-python, wired system-side in modules/nixos/gui/hyprland.nix.
  services.nextcloud-client = {
    enable = true;
    startInBackground = true;
  };
  home.packages = [ config.services.nextcloud-client.package ];
}
