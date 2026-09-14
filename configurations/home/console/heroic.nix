# Heroic's "Add games to Steam automatically" (Settings → General), switched on
# declaratively so every game Heroic installs on the console lands in Steam's
# library for Big Picture without a per-game click.
#
# Heroic keeps the toggle as `defaultSettings.addSteamShortcuts` in
# ~/.config/heroic/config.json (src/backend/constants/paths.ts: configPath =
# join(app.getPath('appData'), 'heroic', 'config.json'); src/backend/config.ts:
# factory default `addSteamShortcuts: false`, and getSettings() spreads the
# factory defaults under whatever the file holds, so a file carrying only this
# key is complete). Not declared through xdg.configFile on purpose:
# GlobalConfig.flush() rewrites the whole file on every Settings change, and a
# read-only store symlink would turn every other Heroic setting into a write
# error. The key is merged into the mutable file at activation instead —
# created if absent, set to true if present — so Kevin's other Heroic settings
# survive and the toggle is re-asserted on every rebuild.
#
# The setting fires src/backend/shortcuts/shortcuts/shortcuts.ts addShortcuts()
# → nonesteamgame.ts addNonSteamGame(), which at the pinned Heroic 2.22.1
# writes userdata/<id>/config/shortcuts.vdf directly with no Steam-running
# check. Steam rewrites that file on exit, so installs have to happen from the
# Hyprland/Noctalia desktop session (modules/nixos/console/desktop.nix) with
# Steam closed for the entry to stick. nixpkgs' fix-non-steam-shortcuts.patch
# makes the shortcut's Exe the bare `heroic` from PATH rather than a store
# path, so entries survive rebuilds.
{ config, lib, pkgs, ... }:
{
  home.activation.heroicSteamShortcuts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    heroicConfig="${config.xdg.configHome}/heroic/config.json"
    jq=${lib.getExe pkgs.jq}
    if [[ -v DRY_RUN ]]; then
      echo "would set defaultSettings.addSteamShortcuts=true in $heroicConfig"
    elif [[ -f "$heroicConfig" ]]; then
      if current="$("$jq" -r '.defaultSettings.addSteamShortcuts' "$heroicConfig" 2>/dev/null)"; then
        if [[ "$current" != "true" ]]; then
          "$jq" '.defaultSettings.addSteamShortcuts = true' "$heroicConfig" > "$heroicConfig.tmp"
          mv "$heroicConfig.tmp" "$heroicConfig"
        fi
      else
        echo "warning: $heroicConfig is not valid JSON; leaving it alone" >&2
      fi
    else
      mkdir -p "$(dirname "$heroicConfig")"
      printf '%s\n' '{"defaultSettings":{"addSteamShortcuts":true},"version":"v0"}' > "$heroicConfig"
    fi
  '';
}
