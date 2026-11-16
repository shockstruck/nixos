# Luciole (noctalia-dev/luciole): the file manager on desktop, laptop and
# console. The Home Manager module comes from the upstream flake input
# (`flake.inputs.luciole.homeModules.default`, wired in flake.nix) and defaults
# `programs.luciole.package` to the flake's own build.
#
# Luciole is the default handler for directories. Its desktop entry only
# declares `inode/directory`, so archive MIME types are not mapped to it.
#
# Programs asking `org.freedesktop.FileManager1` (ShowItems, "show in folder")
# are routed to Luciole by installing its D-Bus activation file under that
# bus name in the user's data directory, as upstream's PACKAGING.md describes.
# GVfs and udisks2 are enabled system-side for Luciole's GIO access.
{ config, flake, ... }:
{
  imports = [ flake.inputs.luciole.homeModules.default ];

  programs.luciole.enable = true;

  xdg.mimeApps = {
    enable = true;
    defaultApplications."inode/directory" = "dev.noctalia.luciole.desktop";
  };

  xdg.dataFile."dbus-1/services/org.freedesktop.FileManager1.service".source =
    "${config.programs.luciole.package}/share/dbus-1/services/dev.noctalia.luciole.FileManager1.service";
}
