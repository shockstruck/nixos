# Callpackaged the same way modules/home/packages.nix consumes
# ../../packages/paperweight.nix.
# lutris (pkgs/by-name/lu/lutris/package.nix) and umu-launcher
# (pkgs/by-name/um/umu-launcher/package.nix) confirmed present in nixpkgs
# source at the pinned rev.
{ pkgs, lib, ... }:
let
  opengameinstaller = pkgs.callPackage ../../../packages/opengameinstaller.nix { };

  # FSR 3.1 -> FSR 4 upgrade on by default for every game run through this
  # tool (proton-cachyos-bin.nix's user_settings.py mechanism); opt out per
  # game with `PROTON_FSR4_UPGRADE=0`. OptiScaler injection is deliberately
  # not defaulted here — it injects a DLL into every game, and upstream
  # calls that path work-in-progress — so it stays per-game via
  # `PROTON_USE_OPTISCALER`. GE-Proton (session.nix) is unaffected: the
  # setting lives in this tool's own directory, not the session.
  protonCachyos = pkgs.callPackage ../../../packages/proton-cachyos-bin.nix {
    userSettings = { PROTON_FSR4_UPGRADE = "1"; };
  };

  # Declarative Steam per-title settings, the ChimeraOS `steam-tweaks` model
  # (chimera_app/steam_config.py) rendered from Nix instead of a downloaded
  # YAML database: compat tool per appid in config/config.vdf
  # (`CompatToolMapping`; appid "0" is Steam's "Run other titles with"
  # default), launch options per appid in every user's
  # userdata/<id>/config/localconfig.vdf. Applied by `steam-tweaks` from
  # console-session (session.nix) right before Steam starts — Steam holds both
  # files in memory and rewrites them on exit, so a Home Manager activation
  # edit during a rebuild would be lost. Re-asserted on every session start;
  # entries not listed here are left exactly as Steam wrote them.
  #
  # Mapping priorities follow what the Steam client itself writes: "0" gets
  # 75, a per-appid entry gets 250 (the value Steam writes for a per-game
  # "Force the use of a specific Steam Play compatibility tool"). The two
  # are not interchangeable. A per-game 250 outranks Steam's built-in
  # preference for a title's native Linux build, which is what makes forcing
  # a native game through Proton work; "0" at 75 does not, so native titles
  # — including the Steam Linux Runtime tool apps themselves — stay native.
  # Writing "0" at 250 forces every title without its own entry through the
  # default Proton, Steam Linux Runtime 4.0 (appid 4183110) included, and
  # Steam then cannot install or update that runtime ("Invalid platform",
  # "unsupported version 0" in logs/compat_log.txt). Every tool whose
  # toolmanifest requires it — Proton 11 and forks such as Proton-CachyOS
  # 11.0 (`require_tool_appid 4183110`) — fails with "Compatibility tool
  # failed", while Proton 10 lineage tools on runtime 3.0 (sniper, 1628350)
  # keep working (ValveSoftware/steam-for-linux#13199, #13248).
  # An entry steam-tweaks already wrote at the wrong priority is corrected
  # in place below.
  steamTweaks = {
    compatToolMapping = {
      "0" = protonCachyos.steamDisplayName;
    };
    launchOptions = { };
  };

  steamTweaksJson = pkgs.writeText "steam-tweaks.json" (builtins.toJSON steamTweaks);

  steamTweaksApply = pkgs.writeShellApplication {
    name = "steam-tweaks";
    runtimeInputs = [ pkgs.coreutils pkgs.procps (pkgs.python3.withPackages (ps: [ ps.vdf ])) ];
    text = ''
      steam_root="''${XDG_DATA_HOME:-$HOME/.local/share}/Steam"
      if pgrep -u "$(id -u)" -x steam > /dev/null 2>&1; then
        echo "steam-tweaks: steam is running; leaving $steam_root alone" >&2
        exit 0
      fi
      exec python3 - "$steam_root" ${steamTweaksJson} <<'PY'
      import json, os, sys, vdf

      steam_root, tweaks_path = sys.argv[1], sys.argv[2]
      with open(tweaks_path, encoding="utf-8") as f:
          tweaks = json.load(f)
      compat = tweaks.get("compatToolMapping", {})
      launch = tweaks.get("launchOptions", {})


      def get_ci(mapping, key):
          # Steam has written both `Valve`/`valve` and `priority`/`Priority`
          # over the years (ProtonUp-Qt steamutil.py, ChimeraOS steam_config.py).
          for k in (key, key.lower(), key.capitalize()):
              if k in mapping:
                  return mapping[k]
          mapping[key] = {}
          return mapping[key]


      def load(path, skeleton):
          if os.path.exists(path):
              with open(path, encoding="utf-8") as f:
                  return vdf.load(f), True
          return skeleton, False


      def save(path, data):
          os.makedirs(os.path.dirname(path), exist_ok=True)
          tmp = path + ".steam-tweaks.tmp"
          with open(tmp, "w", encoding="utf-8") as f:
              vdf.dump(data, f, pretty=True)
          os.replace(tmp, path)


      def apply_compat(path):
          data, existed = load(path, {"InstallConfigStore": {"Software": {"Valve": {"Steam": {}}}}})
          steam = get_ci(get_ci(data["InstallConfigStore"], "Software"), "Valve")
          steam = get_ci(steam, "Steam")
          mapping = steam.setdefault("CompatToolMapping", {})
          changed = not existed
          for appid, tool in compat.items():
              # Steam's own values: 75 for the "0" default, 250 per title.
              priority = "75" if appid == "0" else "250"
              entry = mapping.get(appid)
              if entry is None:
                  mapping[appid] = {"name": tool, "config": "", "priority": priority}
                  changed = True
                  continue
              if entry.get("name") != tool:
                  entry["name"] = tool
                  changed = True
              # Steam has written both `priority` and `Priority`; keep the
              # key that is there rather than adding a second one.
              priority_key = "Priority" if "Priority" in entry else "priority"
              if entry.get(priority_key) != priority:
                  entry[priority_key] = priority
                  changed = True
          if changed:
              save(path, data)
              print(f"steam-tweaks: wrote {len(compat)} compat tool mapping(s) to {path}", file=sys.stderr)


      def apply_launch(path):
          if not launch or not os.path.exists(path):
              return
          data, _ = load(path, None)
          steam = get_ci(get_ci(get_ci(data["UserLocalConfigStore"], "Software"), "Valve"), "Steam")
          apps = steam.setdefault("apps", {})
          changed = False
          for appid, options in launch.items():
              app = apps.setdefault(appid, {})
              if app.get("LaunchOptions") != options:
                  app["LaunchOptions"] = options
                  changed = True
          if changed:
              save(path, data)
              print(f"steam-tweaks: wrote {len(launch)} launch option(s) to {path}", file=sys.stderr)


      apply_compat(os.path.join(steam_root, "config", "config.vdf"))
      userdata = os.path.join(steam_root, "userdata")
      if os.path.isdir(userdata):
          for entry in os.scandir(userdata):
              if entry.is_dir() and entry.name.isdigit() and entry.name != "0":
                  apply_launch(os.path.join(entry.path, "config", "localconfig.vdf"))
      PY
    '';
  };

  # fatboy-unpack (OGI's FitGirl addon) extracts a FuckingFast download by
  # running `unrar x <partN.rar> <dir> -idn -kb -y` once per downloaded
  # volume, sequentially, and fails the whole setup on any non-zero exit.
  # The first run already extracts the entire set (unrar follows
  # part0 -> part1 -> ...); every later run starts on a non-first volume
  # whose first entry continues from the previous one, so unrar prints
  # "You need to start extraction from a previous volume to unpack ..."
  # (loclang.hpp MUnpCannotMerge) and exits 6 (errhnd.hpp RARX_OPEN), which
  # the addon reports as "Failed to extract downloaded files" even though
  # the repack is fully on disk. This wrapper reports success for exactly
  # that case and only for that call signature; anything else — other
  # commands, other switches, other exit codes, other messages — is passed
  # through untouched, so Lutris and umu see the real unrar. Stdout is not
  # intercepted: the addon parses its progress from it. Upstream fix is a
  # one-liner in the addon (extract the first volume only); remove this
  # once it lands.
  unrarFatboy = pkgs.writeShellApplication {
    name = "unrar";
    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep ];
    text = ''
      if [ "$#" -lt 6 ] || [ "$1" != "x" ] \
        || [ "''${*: -3:1}" != "-idn" ] || [ "''${*: -2:1}" != "-kb" ] || [ "''${*: -1}" != "-y" ]; then
        exec ${pkgs.unrar}/bin/unrar "$@"
      fi
      stderr_file="$(mktemp)"
      trap 'rm -f "$stderr_file"' EXIT
      set +e
      ${pkgs.unrar}/bin/unrar "$@" 2> "$stderr_file"
      code=$?
      set -e
      cat "$stderr_file" >&2
      if [ "$code" -eq 6 ] && grep -q 'You need to start extraction from a previous volume' "$stderr_file"; then
        echo "unrar (console wrapper): non-first volume already extracted with its first volume; reporting success" >&2
        exit 0
      fi
      exit "$code"
    '';
  };
in
{
  environment.systemPackages = [
    pkgs.heroic
    pkgs.protonup-qt
    pkgs.mangohud
    pkgs.lutris
    pkgs.umu-launcher
    opengameinstaller
    # OGI's NixOS branch expects Bun on PATH and offers no installer of its own.
    pkgs.bun
    # OGI addons, Lutris and umu extract RAR archives by shelling out to unrar; see unrarFatboy above for why this is a wrapper.
    unrarFatboy
    steamTweaksApply
    # OGI does not use the umu-launcher above for its own Windows-game flow:
    # it downloads the upstream umu zipapp to
    # ~/.local/share/OpenGameInstaller/bin/umu/umu-run (application/src/
    # electron/startup.ts, handlers/handler.umu.ts) and addons spawn it
    # directly for setup.exe / winetricks. That zipapp is a `python3` script
    # (umu-launcher Makefile.in, `python3 -m zipapp … -p`) with pure-Python
    # deps, resolved from PATH — absent here until this line (OGI runs
    # unsandboxed on the host, see packages/opengameinstaller.nix).
    pkgs.python3
  ];

  # umu-launcher (invoked directly by heroic/lutris, and by OGI's own
  # downloaded umu zipapp) reads PROTONPATH as an absolute directory holding
  # a toolmanifest.vdf and skips its own Proton download when set
  # (umu/umu_run.py check_env/resolve_runtime, Open-Wine-Components/
  # umu-launcher). OGI spreads `process.env` into every umu-run it spawns and
  # only overrides PROTONPATH per-game when that game has its own
  # `protonVersion` (application/src/electron/handlers/helpers.app/
  # umu-environment.ts), so this session variable becomes the default Proton
  # for every OGI-managed game, redistributable install and prefix init.
  # `environment.sessionVariables` reaches the greetd autologin -> gamescope
  # -> Steam -> OGI chain via pam_env (modules/config/system-environment.nix,
  # security.pam.services.*.setEnvironment defaults true).
  #
  # Heroic and Lutris set PROTONPATH per game themselves, so this default is
  # only what they fall back to when a game has no per-game Proton chosen.
  # OGI's own per-game Proton picker still lists only entries under
  # `compatibilitytools.d`, not PROTONPATH — Proton-CachyOS being the session
  # default is not currently visible there, a known cosmetic gap.
  environment.sessionVariables.PROTONPATH = "${protonCachyos.steamcompattool}";

  # Also registers as a selectable Steam Play compat tool (Steam reads
  # steamcompattool's compatibilitytool.vdf, programs/steam.nix
  # extraCompatPackages); merges with session.nix's proton-ge-bin.
  programs.steam.extraCompatPackages = [ protonCachyos ];

  # genesis-lib, the OGI addon library behind Cloudflare/DDoS-Guard bypass and
  # the file-host downloaders, resolves its Chromium path on Linux only via
  # `flatpak info --show-location` on this Flathub app id (lib/config.ts); a
  # nixpkgs `chromium` or the console's Brave does not satisfy it, so the
  # addon shows its "install from Flathub" slide without this. Copy of the
  # grayjay-flatpak service in gui/hyprland.nix, not an import.
  systemd.services.chromium-flatpak = {
    description = "Install or update Chromium from Flathub";
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

      if ${pkgs.flatpak}/bin/flatpak info --system org.chromium.Chromium >/dev/null 2>&1; then
        ${pkgs.flatpak}/bin/flatpak update --system --noninteractive org.chromium.Chromium
      else
        ${pkgs.flatpak}/bin/flatpak install --system --noninteractive flathub org.chromium.Chromium
      fi
    '';
  };
}
