# Limo as the console's Nexus Mods client and `nxm://` handler. Nexus Mods
# discontinued the official cross-platform Nexus Mods App in January 2026
# (nexusmods.com/news/15424); nixpkgs' `nexusmods-app` derivation already
# carries that fact as `meta.knownVulnerabilities`
# (pkgs/by-name/ne/nexusmods-app/package.nix), which nixpkgs refuses to
# evaluate without a `permittedInsecurePackages` exception, so it is not used
# here. Limo (`limo-app/limo`) is a native Qt5 mod manager with libloot built
# in, GPL-3.0+, packaged at nixpkgs `pkgs/by-name/li/limo/package.nix`
# (`pname = "limo"`, `version = "1.2.2"`) — unmaintained upstream since its
# last commit `ffdb4f9` (2025-05-03) but the least painful option available.
#
# Limo deploys mods by writing into the game's own directory rather than
# launching or wrapping the game, so it needs no Steam launch hook: titles
# started from Big Picture — native Steam games, and OGI or Heroic
# non-Steam shortcuts alike — pick up deployed mods with no change to
# `steam-tweaks`' compat-tool mapping or umu. It accepts any directory as a
# managed game, so OGI installs (not bought through a store) work the same
# as Steam/Heroic titles. Workflow: switch to this Hyprland/Noctalia desktop
# session, click a "Mod Manager Download" nxm link in Brave, Limo deploys,
# switch back to the gamescope session.
#
# `withUnrar` is left at its nixpkgs default of `false`
# (pkgs/by-name/li/limo/package.nix): turning it on pulls in the unfree
# `unrar`, which the public binary cache does not build, so Limo would
# compile from source on every rebuild. Limo's bundled libarchive already
# reads RAR4/RAR5; unrar is only a fallback for archives libarchive can't
# open.
#
# Upstream's `install_files/limo.desktop` (limo-app/limo @ v1.2.2) declares
# `MimeType=x-scheme-handler/nxm;` with `Exec=limo %u`, so setting it as the
# default `x-scheme-handler/nxm` handler here is enough for `nxm://` links
# to open in Limo once it is installed. `xdg.mimeApps.enable` and
# `defaultApplications` are home-manager's `modules/misc/xdg/mime-apps.nix`
# options; setting `enable = true` here merges cleanly with
# `modules/home/archives.nix`'s own `xdg.mimeApps.enable = true` (home-manager
# merges equal values for `types.bool` options) and its
# `defaultApplications` maps disjoint MIME keys (archive types, not `nxm`).
#
# Limo 1.2.2 leans on standard headers arriving transitively, which GCC 16's
# libstdc++ no longer does: the build stops at "'uint64_t' was not declared"
# (<cstdint>), then "'put_time' is not a member of 'std'" (<iomanip>), and the
# sources use more of the standard library the same way. Upstream is
# unmaintained, so every C++ translation unit force-includes the headers it
# relies on. The project is C++-only (`LANGUAGES CXX`), and a header that is
# already included is a no-op. `cmakeFlagsArray` keeps the space-separated
# value as a single flag.
#
# `limo-sync` and the `limo` wrapper (below) close the gap that Limo has no
# detection of its own: its Steam import is a manual dialog, one game per run
# (src/ui/importfromsteamdialog.cpp), and it cannot see OGI installs at all.
# Opening Limo through the wrapper first runs `limo-sync`, which registers
# every installed Steam and OGI game Limo does not already manage, seeded the
# way Limo's own import would seed it. It never touches an existing app's
# `lmm_mods.json`, and edits only the `[staging_directories]` section of
# `~/.config/Limo.conf` (the `[nexus]` section holds the encrypted API key).
# It also writes `~/.config/limo-sync/nxm-domains.json`, mapping a Nexus
# `game_domain` to a Limo app name; the patch in
# `limo-nxm-domain-routing.patch` reads it so an nxm link installs into that
# app (Limo 1.2.2 alone uses the app currently selected).
{ lib, pkgs, ... }:
let
  forcedIncludes = [
    "algorithm"
    "array"
    "chrono"
    "cstdint"
    "functional"
    "iomanip"
    "limits"
    "memory"
    "optional"
    "sstream"
    "stdexcept"
  ];
  limo = pkgs.limo.overrideAttrs (prev: {
    # Routes an nxm:// link to the Limo app named for its game domain in
    # limo-sync's nxm-domains.json; Limo 1.2.2 installs into the selected app.
    patches = (prev.patches or [ ]) ++ [ ./limo-nxm-domain-routing.patch ];
    preConfigure = (prev.preConfigure or "") + ''
      cmakeFlagsArray+=("-DCMAKE_CXX_FLAGS=${lib.concatMapStringsSep " " (h: "-include ${h}") forcedIncludes}")
    '';
  });

  # Nexus `game_domain` for a game, keyed by Steam appid or by exact lowercased
  # title (for an OGI install with no Steam id). Every slug was checked
  # against Nexus's own games list (data.nexusmods.com/file/nexus-data/
  # games.json) and the appid against its Steam store page. To add a game:
  # find its `domain_name` in that list (the path of its nexusmods.com page),
  # then add `"<steam appid>" = "<domain>";` under `steam` and, for a game
  # installed outside Steam, `"<title in lowercase>" = "<domain>";` under
  # `title`. Skyrim VR has no domain of its own on Nexus: its mods live under
  # `skyrimspecialedition` (Vortex's game-skyrimvr extension, nexusPageId).
  nexusDomains = {
    steam = {
      "22300" = "fallout3"; # Fallout 3
      "22330" = "oblivion"; # The Elder Scrolls IV: Oblivion GOTY
      "22370" = "fallout3"; # Fallout 3: GOTY
      "22380" = "newvegas"; # Fallout: New Vegas
      "72850" = "skyrim"; # The Elder Scrolls V: Skyrim
      "264710" = "subnautica"; # Subnautica
      "377160" = "fallout4"; # Fallout 4
      "413150" = "stardewvalley"; # Stardew Valley
      "489830" = "skyrimspecialedition"; # Skyrim Special Edition
      "611670" = "skyrimspecialedition"; # Skyrim VR
      "848450" = "subnauticabelowzero"; # Subnautica: Below Zero
      "900883" = "oblivion"; # Oblivion GOTY Deluxe
      "1086940" = "baldursgate3"; # Baldur's Gate 3
      "1091500" = "cyberpunk2077"; # Cyberpunk 2077
      "292030" = "witcher3"; # The Witcher 3: Wild Hunt
      "1245620" = "eldenring"; # Elden Ring
      "1716740" = "starfield"; # Starfield
    };
    title = {
      "baldur's gate 3" = "baldursgate3";
      "cyberpunk 2077" = "cyberpunk2077";
      "elden ring" = "eldenring";
      "fallout 3" = "fallout3";
      "fallout 4" = "fallout4";
      "fallout new vegas" = "newvegas";
      "oblivion" = "oblivion";
      "skyrim" = "skyrim";
      "skyrim special edition" = "skyrimspecialedition";
      "starfield" = "starfield";
      "stardew valley" = "stardewvalley";
      "subnautica" = "subnautica";
      "subnautica: below zero" = "subnauticabelowzero";
      "the witcher 3: wild hunt" = "witcher3";
    };
  };

  # Tools Steam lists as installed apps that are not games. The appids are
  # the Steam Linux Runtime ones steam-tweaks refuses to map
  # (modules/nixos/console/launchers.nix, RUNTIME_APPIDS) and must stay in
  # step with it; 228980 is Steamworks Common Redistributables.
  skip = {
    appIds = [ "228980" "1070560" "1391110" "1628350" "4183110" "4185400" ];
    namePatterns = [ "^Proton" "^Steam Linux Runtime" "^Steamworks Common Redistributables" ];
  };

  limoSyncJson = pkgs.writeText "limo-sync.json" (builtins.toJSON {
    inherit nexusDomains skip;
    # The shipped per-game deployer configs: CMakeLists.txt installs
    # `steam_app_configs` to ${LIMO_INSTALL_PREFIX}/share/limo, which
    # nixpkgs' limo package sets to $out (package.nix, `LIMO_INSTALL_PREFIX`).
    configsDir = "${limo}/share/limo/steam_app_configs";
    # DeployerFactory::DEPLOYER_TYPES (src/core/deployerfactory.h:33-39 @ v1.2.2).
    deployerTypes = [
      "Case Matching Deployer"
      "Simple Deployer"
      "Loot Deployer"
      "Reverse Deployer"
      "OpenMW Plugin Deployer"
      "OpenMW Archive Deployer"
      "Baldurs Gate 3 Deployer"
    ];
  });

  limoSync = pkgs.writeShellApplication {
    name = "limo-sync";
    runtimeInputs = [ pkgs.coreutils (pkgs.python3.withPackages (ps: [ ps.vdf ])) ];
    text = ''
      exec python3 - ${limoSyncJson} <<'PY'
      import json, os, re, shutil, sys, tempfile, vdf

      with open(sys.argv[1], encoding="utf-8") as f:
          CFG = json.load(f)

      HOME = os.path.expanduser("~")
      DATA_HOME = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local/share")
      CONFIG_HOME = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
      STEAM_ROOT = os.path.join(DATA_HOME, "Steam")
      OGI_DIR = os.environ.get("OGI_DIRECTORY") or os.path.join(DATA_HOME, "OpenGameInstaller")
      STAGING_ROOT = os.path.join(DATA_HOME, "limo", "staging")
      LIMO_CONF = os.path.join(CONFIG_HOME, "Limo.conf")
      SIDECAR = os.path.join(CONFIG_HOME, "limo-sync", "nxm-domains.json")
      SECTION = "staging_directories"
      CONFIG_FILE_NAME = "lmm_mods.json"

      DEPLOYER_TYPES = CFG["deployerTypes"]
      SKIP_APPIDS = set(CFG["skip"]["appIds"])
      SKIP_NAME_RES = [re.compile(p) for p in CFG["skip"]["namePatterns"]]
      DOMAINS_STEAM = CFG["nexusDomains"]["steam"]
      DOMAINS_TITLE = CFG["nexusDomains"]["title"]


      def log(msg):
          print(f"limo-sync: {msg}", file=sys.stderr)


      def atomic_write(path, data, mode_from=None):
          os.makedirs(os.path.dirname(path), exist_ok=True)
          fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".limo-sync.")
          try:
              with os.fdopen(fd, "wb") as f:
                  f.write(data)
              if mode_from and os.path.exists(mode_from):
                  shutil.copymode(mode_from, tmp)
              os.replace(tmp, path)
          except BaseException:
              if os.path.exists(tmp):
                  os.unlink(tmp)
              raise


      def read_json(path):
          try:
              with open(path, encoding="utf-8") as f:
                  return json.load(f)
          except (OSError, ValueError):
              return None


      # Qt's QSettings INI string escaping (qtbase 5.15 qsettings.cpp,
      # QSettingsPrivate::iniEscapedString, no codec set): quote on ; , = or a
      # leading/trailing space, backslash-escape " and \, and write every control
      # or non-ASCII UTF-16 unit as \x<hex>, escaping a hex digit that follows one.
      def ini_escape(s):
          out = []
          needs_quotes = False
          esc_digit = False
          units = s.encode("utf-16-le")
          for i in range(0, len(units), 2):
              ch = units[i] | (units[i + 1] << 8)
              if ch in (0x3B, 0x2C, 0x3D):
                  needs_quotes = True
              c = chr(ch)
              if esc_digit and c in "0123456789abcdefABCDEF":
                  out.append("\\x%x" % ch)
                  continue
              esc_digit = False
              if ch == 0:
                  out.append("\\0")
                  esc_digit = True
              elif c in "\a\b\f\n\r\t\v":
                  out.append({"\a": "\\a", "\b": "\\b", "\f": "\\f", "\n": "\\n",
                              "\r": "\\r", "\t": "\\t", "\v": "\\v"}[c])
              elif c in '"\\':
                  out.append("\\" + c)
              elif ch <= 0x1F or ch >= 0x7F:
                  out.append("\\x%x" % ch)
                  esc_digit = True
              else:
                  out.append(c)
          res = "".join(out)
          if needs_quotes or res.startswith(" ") or res.endswith(" "):
              res = '"' + res + '"'
          return res


      def ini_unescape(v):
          v = v.strip()
          if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
              v = v[1:-1]
          out = bytearray()
          i = 0
          simple = {"a": 7, "b": 8, "f": 12, "n": 10, "r": 13, "t": 9, "v": 11}
          while i < len(v):
              c = v[i]
              if c == "\\" and i + 1 < len(v):
                  n = v[i + 1]
                  if n in simple:
                      out.append(simple[n])
                      i += 2
                  elif n == "x":
                      m = re.match(r"[0-9a-fA-F]{1,4}", v[i + 2:])
                      if m:
                          out += chr(int(m.group(0), 16)).encode("utf-8", "replace")
                          i += 2 + len(m.group(0))
                      else:
                          i += 2
                  else:
                      out += n.encode("utf-8")
                      i += 2
              else:
                  out += c.encode("utf-8")
                  i += 1
          return out.decode("utf-8", "replace")


      def parse_registry(text):
          # Returns (paths in array order, section line span or None, size line
          # index or None, last entry/size line index). Line-level only: nothing
          # outside the span is interpreted.
          lines = text.split("\n")
          start = None
          for idx, line in enumerate(lines):
              m = re.match(r"^\[(.*)\]\s*$", line)
              if m:
                  if start is not None:
                      return lines, start, idx
                  if m.group(1) == SECTION:
                      start = idx
          return lines, start, len(lines) if start is not None else None


      def registry_paths(lines, start, end):
          paths = {}
          size = None
          for line in lines[start + 1:end]:
              m = re.match(r"^(\d+)\\(\d+)=(.*?)\r?$", line)
              if m:
                  paths[int(m.group(2))] = ini_unescape(m.group(3))
                  continue
              m = re.match(r"^size=(\d+)\s*$", line)
              if m:
                  size = int(m.group(1))
          n = size if size is not None else (max(paths) + 1 if paths else 0)
          return [paths[i] for i in range(n) if i in paths], n


      def norm(p):
          return os.path.normpath(p) if p else p


      def steam_games():
          vf = os.path.join(STEAM_ROOT, "steamapps", "libraryfolders.vdf")
          if not os.path.isfile(vf):
              return []
          with open(vf, encoding="utf-8", errors="replace") as f:
              data = vdf.load(f)
          folders = {k.lower(): v for k, v in data.items()}.get("libraryfolders", {})
          libs = []
          for key, entry in folders.items():
              if isinstance(entry, dict) and entry.get("path"):
                  libs.append(entry["path"])
              elif isinstance(entry, str) and key.isdigit():
                  libs.append(entry)
          games, seen = [], set()
          for lib in libs:
              steamapps = os.path.join(lib, "steamapps")
              try:
                  names = sorted(os.listdir(steamapps))
              except OSError:
                  continue
              for fn in names:
                  m = re.fullmatch(r"appmanifest_(\d+)\.acf", fn)
                  if not m or m.group(1) in seen:
                      continue
                  appid = m.group(1)
                  try:
                      with open(os.path.join(steamapps, fn), encoding="utf-8", errors="replace") as f:
                          state = vdf.load(f).get("AppState", {})
                  except (OSError, SyntaxError):
                      continue
                  name, installdir = state.get("name"), state.get("installdir")
                  if not name or not installdir:
                      continue
                  try:
                      if not int(state.get("StateFlags", "4")) & 4:
                          continue
                  except ValueError:
                      pass
                  if appid in SKIP_APPIDS or any(r.search(name) for r in SKIP_NAME_RES):
                      continue
                  install = os.path.join(steamapps, "common", installdir)
                  if not os.path.isdir(install):
                      continue
                  prefix = ""
                  if os.path.exists(os.path.join(steamapps, "compatdata", appid)):
                      prefix = os.path.join(steamapps, "compatdata", appid, "pfx", "drive_c")
                  seen.add(appid)
                  games.append({"key": f"steam-{appid}", "source": "Steam", "title": name,
                                "command": f"steam steam://rungameid/{appid}",
                                "steam_id": int(appid), "install": install, "prefix": prefix})
          return games


      def ogi_games():
          lib = os.path.join(OGI_DIR, "library")
          try:
              names = sorted(os.listdir(lib))
          except OSError:
              return []
          games = []
          for fn in names:
              if not re.fullmatch(r"\d+\.json", fn):
                  continue
              rec = read_json(os.path.join(lib, fn))
              if not isinstance(rec, dict):
                  continue
              name, cwd, app_id = rec.get("name"), rec.get("cwd"), rec.get("appID")
              if not isinstance(name, str) or not name or not isinstance(cwd, str) or app_id is None:
                  continue
              if not os.path.isdir(cwd):
                  continue
              steam_id, prefix = -1, ""
              umu = rec.get("umu")
              if isinstance(umu, dict):
                  m = re.fullmatch(r"steam:(\d+)", str(umu.get("umuId", "")))
                  if m:
                      steam_id = int(m.group(1))
                  wp = umu.get("winePrefixPath")
                  if isinstance(wp, str) and wp:
                      prefix = os.path.join(wp, "drive_c") if os.path.isdir(os.path.join(wp, "drive_c")) else wp
              games.append({"key": f"ogi-{app_id}", "source": "OGI", "title": name,
                            "command": f"opengameinstaller --game-id={app_id}",
                            "steam_id": steam_id, "install": cwd, "prefix": prefix})
          return games


      def default_deployers(install, prefix):
          return [("Case Matching Deployer", "Install", install, 0, None),
                  ("Case Matching Deployer", "Prefix", prefix, 0, None)]


      # Mirrors AddAppDialog::initConfigForApp / initDefaultAppConfig
      # (limo-app/limo v1.2.2 src/ui/addappdialog.cpp:105-300). Returns the
      # config-supplied name (or None), deployer tuples and auto tags.
      def limo_config(steam_id, install, prefix):
          name, deployers, tags = None, [], []
          cfg = read_json(os.path.join(CFG["configsDir"], f"{steam_id}.json")) if steam_id > 0 else None
          if isinstance(cfg, dict):
              for d in cfg.get("deployers") or []:
                  dtype = d.get("type", "")
                  if dtype not in DEPLOYER_TYPES:
                      continue
                  sub = lambda s: s.replace("$STEAM_INSTALL_PATH$", install).replace("$STEAM_PREFIX_PATH$", prefix)
                  target = sub(d.get("target_dir", ""))
                  if not os.path.exists(target):
                      continue
                  mode = str(d.get("deploy_mode", "")).lower()
                  # Deliberate deviation from Limo: its parser (addappdialog.cpp:201)
                  # only accepts "hard link", so it drops the deployers of the five
                  # shipped configs that spell it "hard_link" (22380, 264710, 413150,
                  # 489830, 848450). They clearly mean a hard link; accept both.
                  if mode in ("hard link", "hard_link"):
                      mode = 0
                  elif mode in ("sym link", "soft link"):
                      mode = 1
                  elif mode == "copy":
                      mode = 2
                  else:
                      continue
                  source = None
                  if d.get("source_dir") is not None:
                      source = sub(d["source_dir"]).replace("$HOME$", HOME)
                      if not os.path.exists(source):
                          continue
                  deployers.append((dtype, d.get("name", ""), target, mode, source))
              tags = [t for t in cfg.get("auto_tags") or []
                      if isinstance(t, dict) and t.get("name") and t.get("expression")]
              if cfg.get("name") is not None:
                  name = cfg["name"]
          if not deployers and not tags:
              deployers = default_deployers(install, prefix)
          # Limo keeps a default deployer whose target is missing; the design for
          # this reconciler drops it (a deployer pointing nowhere cannot work).
          deployers = [d for d in deployers if d[2] and os.path.exists(d[2])]
          return name, deployers, tags


      # Deployer::fixInvalidLinkDeployMode (src/core/deployer.cpp:860-890): the
      # test link's source file never exists, so it always fails and a hard link
      # deployer is stored as a sym link (1). Run literally rather than assumed.
      def fix_link_mode(staging, target, mode):
          if mode != 0:
              return mode
          probe = "_lmm_write_test_file_"
          try:
              for d in (staging, target):
                  if os.path.lexists(os.path.join(d, probe)):
                      os.remove(os.path.join(d, probe))
              os.link(os.path.join(staging, probe), os.path.join(target, probe))
              os.remove(os.path.join(target, probe))
              return 0
          except OSError:
              return 1


      # DeployerFactory::AUTONOMOUS_DEPLOYERS (deployerfactory.h:72-79). Their
      # `source_path` is the deployer's own source dir and updateSettings
      # (moddedapplication.cpp:1604-1640) writes no `profiles` for them. A Reverse
      # Deployer would need a rev_depl_N source dir (moddedapplication.cpp:536-544);
      # no shipped config or default uses one, so it is skipped.
      AUTONOMOUS_TYPES = {"Loot Deployer", "OpenMW Plugin Deployer", "OpenMW Archive Deployer",
                          "Baldurs Gate 3 Deployer"}


      def seed_json(game, name, staging, deployers, tags):
          out = []
          for dtype, dname, target, mode, source in deployers:
              autonomous = dtype in AUTONOMOUS_TYPES
              if (autonomous and not source) or dtype == "Reverse Deployer":
                  log(f"skipping deployer {dname} ({dtype}) of {name}: no usable source")
                  continue
              entry = {
                  "dest_path": target,
                  "source_path": source if autonomous else staging,
                  "name": dname,
                  "type": dtype,
                  # The Loot Deployer constructor forces copy (lootdeployer.cpp:24).
                  "deploy_mode": 2 if dtype == "Loot Deployer" else fix_link_mode(staging, target, mode),
                  "enable_unsafe_sorting": True,
              }
              if not autonomous:
                  entry["profiles"] = [{"name": "Default"}]
              out.append(entry)
          doc = {"name": name, "command": game["command"], "icon_path": "",
                 "profiles": [{"name": "Default", "app_version": ""}],
                 "deployers": out, "steam_app_id": game["steam_id"]}
          if tags:
              doc["auto_tags"] = tags
          return doc


      def sync():
          try:
              with open(LIMO_CONF, "rb") as f:
                  raw = f.read()
          except FileNotFoundError:
              raw = b""
          text = raw.decode("latin-1")
          eol = "\r\n" if "\r\n" in text else "\n"
          lines, start, end = parse_registry(text)
          registered, count = ([], 0)
          if start is not None:
              registered, count = registry_paths(lines, start, end)

          apps = []  # registered apps: dicts with name, steam_id, dests, titles
          reg_set = set(norm(p) for p in registered)
          for p in registered:
              doc = read_json(os.path.join(p, CONFIG_FILE_NAME))
              if not isinstance(doc, dict):
                  continue
              apps.append({"name": doc.get("name", ""), "steam_id": doc.get("steam_app_id", -1),
                           "dests": [norm(d.get("dest_path", "")) for d in doc.get("deployers") or []
                                     if isinstance(d, dict)],
                           "titles": [doc.get("name", "")]})
          names = set(a["name"] for a in apps)
          steam_ids = set(a["steam_id"] for a in apps if isinstance(a["steam_id"], int) and a["steam_id"] != -1)
          dests = set(d for a in apps for d in a["dests"])

          new_paths = []
          for game in steam_games() + ogi_games():
              staging = os.path.join(STAGING_ROOT, game["key"])
              if norm(staging) in reg_set:
                  continue
              if game["steam_id"] != -1 and game["steam_id"] in steam_ids:
                  continue
              if norm(game["install"]) in dests:
                  continue
              cfg_name, deployers, tags = limo_config(game["steam_id"], game["install"], game["prefix"])
              name = cfg_name or game["title"]
              if name in names:
                  name = f"{name} ({game['source']})"
                  if name in names:
                      name = f"{name} {game['key']}"
              conf = os.path.join(staging, CONFIG_FILE_NAME)
              if os.path.exists(conf):
                  # A previous run seeded this directory but never registered it:
                  # register it as it stands, never rewrite the file.
                  doc = read_json(conf)
                  if not (isinstance(doc, dict) and all(k in doc for k in ("name", "command", "icon_path", "profiles"))):
                      log(f"{staging} holds an unreadable {CONFIG_FILE_NAME}; skipping {game['title']}")
                      continue
                  name = doc["name"]
              else:
                  os.makedirs(staging, exist_ok=True)
                  doc = seed_json(game, name, staging, deployers, tags)
                  atomic_write(conf, (json.dumps(doc, indent=2, sort_keys=True) + "\n").encode("utf-8"))
              new_paths.append(staging)
              reg_set.add(norm(staging))
              names.add(name)
              if game["steam_id"] != -1:
                  steam_ids.add(game["steam_id"])
              dests.add(norm(game["install"]))
              for d in doc.get("deployers") or []:
                  dests.add(norm(d.get("dest_path", "")))
              apps.append({"name": name, "steam_id": game["steam_id"], "dests": [],
                           "titles": [name, game["title"]]})
              log(f"added {name} ({game['key']})")

          if new_paths:
              entries = [f"{count + 1 + i}\\{count + i}={ini_escape(p)}" for i, p in enumerate(new_paths)]
              size_line = f"size={count + len(new_paths)}"
              if start is None:
                  head = text
                  if head and not head.endswith("\n"):
                      head += eol
                  if head:
                      head += eol
                  new_text = head + f"[{SECTION}]" + eol + eol.join(entries + [size_line]) + eol
              else:
                  body = lines[start + 1:end]
                  last = max((i for i, l in enumerate(body) if l.strip()), default=-1)
                  size_at = next((i for i, l in enumerate(body) if re.match(r"^size=\d+\s*$", l)), None)
                  add = [e + ("\r" if eol == "\r\n" else "") for e in entries]
                  if size_at is not None:
                      body[size_at] = size_line + ("\r" if eol == "\r\n" else "")
                      body[size_at:size_at] = add
                  else:
                      body[last + 1:last + 1] = add + [size_line + ("\r" if eol == "\r\n" else "")]
                  new_text = "\n".join(lines[:start + 1] + body + lines[end:])
              if raw:
                  shutil.copy2(LIMO_CONF, LIMO_CONF + ".limo-sync.bak")
              atomic_write(LIMO_CONF, new_text.encode("latin-1"), mode_from=LIMO_CONF)

          claims = {}
          for a in apps:
              dom = DOMAINS_STEAM.get(str(a["steam_id"])) if isinstance(a["steam_id"], int) else None
              if dom is None:
                  for t in a["titles"]:
                      dom = DOMAINS_TITLE.get(str(t).lower())
                      if dom:
                          break
              if dom:
                  claims.setdefault(dom, []).append(a["name"])
          sidecar = {}
          for dom, owners in sorted(claims.items()):
              if len(owners) == 1:
                  sidecar[dom] = owners[0]
              else:
                  log(f"domain {dom} claimed by {', '.join(sorted(owners))}; omitted")
          data = (json.dumps(sidecar, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")
          try:
              with open(SIDECAR, "rb") as f:
                  same = f.read() == data
          except OSError:
              same = False
          if not same:
              atomic_write(SIDECAR, data)


      try:
          sync()
      except Exception as exc:
          log(f"failed: {exc!r}")
          sys.exit(1)
      PY
    '';
  };

  # `limo` on PATH (and so the upstream `limo.desktop`, `Exec=limo %u`, and the
  # `x-scheme-handler/nxm` default below) resolves to this wrapper: in a
  # symlinkJoin the first path wins a name clash, and the wrapper's
  # `bin/limo` shadows the real one. Limo's own `limo` is a Qt wrapper script
  # around `.limo-wrapped`, so a running Limo shows up as either name under
  # the real package's store path. If one is running for this user the sync is
  # skipped, so the IPC hand-off of an nxm link to the open window is
  # unchanged; and a failed or hung sync never stops Limo from starting.
  limoWrapper = pkgs.writeShellApplication {
    name = "limo";
    runtimeInputs = [ pkgs.coreutils pkgs.procps pkgs.systemd limoSync ];
    text = ''
      if ! pgrep -u "$(id -u)" -f '^${lib.escapeRegex "${limo}"}/bin/(\.limo-wrapped|limo)( |$)' > /dev/null 2>&1; then
        { timeout 60 limo-sync 2>&1 || echo "limo-sync exited with status $?"; } | systemd-cat -t limo-sync || true
      fi
      exec ${limo}/bin/limo "$@"
    '';
  };

  limoWithSync = pkgs.symlinkJoin {
    name = "limo-with-sync";
    paths = [ limoWrapper limoSync limo ];
    # Make the clash resolution explicit rather than relying on path order.
    postBuild = "ln -sf ${limoWrapper}/bin/limo $out/bin/limo";
    meta.mainProgram = "limo";
  };
in
{
  home.packages = [ limoWithSync ];

  xdg.mimeApps = {
    enable = true;
    defaultApplications."x-scheme-handler/nxm" = "limo.desktop";
  };
}
