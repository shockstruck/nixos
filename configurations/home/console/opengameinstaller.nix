# OGI creates its main window non-resizable (application/src/electron/main.ts
# createWindow: resizable is false outside a Steam wrapper launch), so Electron
# publishes X11 size hints with min == max and Hyprland's on-map heuristic
# floats it at 1000x700 over the tiled layout. Force it tiled. `tile` alone is
# not enough: the dwindle layout re-floats any window whose max-size hint is
# smaller than the slot it would get (DwindleAlgorithm.cpp addTarget), so the
# max hint has to be ignored as well. Both are hl.window_rule effect fields at
# the pinned Hyprland (src/config/lua/bindings/LuaBindingsInternal.hpp).
# Class is Electron's app name, `opengameinstaller-gui` (application/
# package.json); matched case-insensitively with the suffix optional so a
# casing or naming drift cannot silently miss. The startup splash shares the
# class and title, so it tiles for the seconds it exists — accepted, nothing
# distinguishes the two windows.
#
# Console-only: OGI is installed only by modules/nixos/console/launchers.nix.
{ ... }:
{
  wayland.windowManager.hyprland.settings.window_rule = [
    {
      name = "opengameinstaller-tile";
      match.class = "(?i)^opengameinstaller(-gui)?$";
      tile = true;
      no_max_size = true;
    }
  ];
}
