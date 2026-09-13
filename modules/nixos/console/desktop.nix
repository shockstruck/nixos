# The console's answer to Big Picture's "Switch to Desktop": a Hyprland/
# Noctalia session reachable via console-session (./session.nix), for the
# couch-side desktop use cases Steam's own client can't cover (OGI's and
# Heroic's Steam-shortcut writers both need Steam closed while they run).
#
# This is a copy of modules/nixos/gui/hyprland.nix's system-layer pieces, not
# an import of it: gui/hyprland.nix also enables
# services.displayManager.noctalia-greeter, which would define
# services.greetd.settings.default_session a second time — an eval conflict
# with ./session.nix, which already owns greetd on this host with its own
# tuigreet fallback. Importing modules/nixos/gui wholesale would additionally
# drag in the Grayjay flatpak service and kdeconnect, neither of which
# belongs on a console. Brave's managed-policy file is imported below
# instead, by its own relative path: it is a standalone /etc entry, so
# pulling it in on its own carries no greeter or other gui/ pieces.
#
# Deliberately absent, unlike gui/hyprland.nix:
#   - services.displayManager.noctalia-greeter (greetd conflict above; this
#     host's greeter is console-session/tuigreet)
#   - programs.steam (already configured by ./session.nix, gamescope-first)
#   - the grayjay-flatpak install/update service, kdeconnect
#   - services.gnome.gnome-keyring, services.gvfs, services.udisks2 — no
#     desktop file manager or GNOME-keyring-consuming app runs here
#   - services.xserver.enable — Hyprland is Wayland-native and needs no X
#     server stack (gui/default.nix only turns this on for its own reasons)
#
# Verified against nixpkgs source before writing:
#   nixos/modules/programs/wayland/hyprland.nix: programs.hyprland.enable
#     (mkEnableOption) and programs.hyprland.xwayland.enable (mkEnableOption,
#     default true already, kept explicit here for parity with gui/hyprland.nix).
#   nixos/modules/config/system-path.nix: environment.pathsToLink
#     (listOf str).
{ pkgs, ... }:
{
  imports = [ ../gui/brave.nix ];

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  environment.pathsToLink = [ "/share/applications" "/share/xdg-desktop-portal" ];

  # Noctalia's icon/text fonts, copied verbatim from gui/hyprland.nix so the
  # shell renders identically to desktop/laptop.
  fonts.packages = [
    (pkgs.google-fonts.override {
      fonts = [ "Google Sans Flex" "Readex Pro" "Space Grotesk" ];
    })
    pkgs.material-symbols
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.rubik
    pkgs.twemoji-color-font
  ];
}
