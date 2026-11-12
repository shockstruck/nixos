{ config, lib, pkgs, ... }:
{
  programs.brave-origin = {
    enable = true;
    extensions = [
      "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
    ];
  };

  # Wide address bar has no Chromium/Brave policy: brave-core's
  # browser/policy/brave_simple_policy_map.h lists every Brave policy and
  # none covers it. It's the plain profile pref brave.location_bar_is_wide
  # (components/constants/pref_names.h, default false in
  # browser/brave_profile_prefs.cc), which only lives in the profile's
  # mutable Preferences file — not declared via xdg.configFile because Brave
  # rewrites Preferences wholesale on every run and exit, which would fight a
  # read-only store symlink. The key is merged in at activation instead, with
  # a SingletonLock guard: Brave holds that lock while running and rewrites
  # Preferences on exit, so an edit made while it's open would be clobbered;
  # if it's running we skip and the setting lands on the activation after
  # Brave is next closed. A profile that has never launched has no
  # Preferences file yet, so nothing is created — the setting is picked up on
  # the first activation after that profile's first launch.
  home.activation.braveWideLocationBar = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dataDir="${config.xdg.configHome}/BraveSoftware/Brave-Origin"
    jq=${lib.getExe pkgs.jq}
    if [[ -v DRY_RUN ]]; then
      echo "would set brave.location_bar_is_wide=true in $dataDir/*/Preferences"
    elif [[ -L "$dataDir/SingletonLock" ]]; then
      echo "warning: Brave is running; wide address bar will be applied on the next activation with Brave closed" >&2
    elif [[ -d "$dataDir" ]]; then
      for prefs in "$dataDir"/*/Preferences; do
        [[ -f "$prefs" ]] || continue
        if current="$("$jq" -r '.brave.location_bar_is_wide' "$prefs" 2>/dev/null)"; then
          if [[ "$current" != "true" ]]; then
            "$jq" '.brave.location_bar_is_wide = true' "$prefs" > "$prefs.tmp"
            mv "$prefs.tmp" "$prefs"
          fi
        else
          echo "warning: $prefs is not valid JSON; leaving it alone" >&2
        fi
      done
    fi
  '';
}
