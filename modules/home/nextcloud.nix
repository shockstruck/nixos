{ config, ... }:
{
  # Nextcloud desktop sync client, started with the graphical session by
  # home-manager's services.nextcloud-client unit. That module only defines
  # the systemd user unit, so the package is added to home.packages
  # explicitly: that is what puts its .desktop entry and the
  # org.freedesktop.CloudProviders D-Bus activation file in the profile.
  services.nextcloud-client = {
    enable = true;
    startInBackground = true;
  };
  home.packages = [ config.services.nextcloud-client.package ];
}
