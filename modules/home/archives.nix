{ pkgs, ... }:
{
  # Nautilus 50 dropped the `automatic-decompression` gsettings key; it now
  # extracts in place with no dialog whenever the archive's MIME type's XDG
  # default application is Nautilus itself (nautilus-mime-actions.c's
  # get_activation_action() returns ACTIVATION_ACTION_EXTRACT, and
  # nautilus-files-view.c calls extract_files() straight away). So the
  # mimeapps.list defaults below are what make double-click auto-extract,
  # not a Nautilus setting. Nautilus's own .desktop entry already lists
  # these MIME types, so only Default Applications is needed here.
  home.packages = with pkgs; [
    zip
    unzip
    p7zip
  ];

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "application/zip" = "org.gnome.Nautilus.desktop";
      "application/x-7z-compressed" = "org.gnome.Nautilus.desktop";
      "application/x-7z-compressed-tar" = "org.gnome.Nautilus.desktop";
      "application/x-tar" = "org.gnome.Nautilus.desktop";
      "application/x-compressed-tar" = "org.gnome.Nautilus.desktop";
      "application/x-bzip-compressed-tar" = "org.gnome.Nautilus.desktop";
      "application/x-bzip2-compressed-tar" = "org.gnome.Nautilus.desktop";
      "application/x-xz-compressed-tar" = "org.gnome.Nautilus.desktop";
      "application/x-zstd-compressed-tar" = "org.gnome.Nautilus.desktop";
      "application/x-lzma-compressed-tar" = "org.gnome.Nautilus.desktop";
      "application/x-lzip-compressed-tar" = "org.gnome.Nautilus.desktop";
      "application/gzip" = "org.gnome.Nautilus.desktop";
      "application/x-gzip" = "org.gnome.Nautilus.desktop";
      "application/bzip2" = "org.gnome.Nautilus.desktop";
      "application/x-bzip" = "org.gnome.Nautilus.desktop";
      "application/x-xz" = "org.gnome.Nautilus.desktop";
      "application/zstd" = "org.gnome.Nautilus.desktop";
      "application/x-lzma" = "org.gnome.Nautilus.desktop";
      "application/x-lzip" = "org.gnome.Nautilus.desktop";
      "application/x-compress" = "org.gnome.Nautilus.desktop";
      "application/x-tarz" = "org.gnome.Nautilus.desktop";
      "application/x-cpio" = "org.gnome.Nautilus.desktop";
      "application/x-lha" = "org.gnome.Nautilus.desktop";
      "application/x-xar" = "org.gnome.Nautilus.desktop";
      "application/vnd.rar" = "org.gnome.Nautilus.desktop";
    };
  };
}
