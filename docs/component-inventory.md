# Component inventory

Captured against `origin/main` @ `fae580b` (2026-10-10). This doc is not
imported by the flake and does not affect the build; it is a living inventory
that must be re-verified against `main` whenever the flake changes.

## Flake inputs

Every top-level input of `flake.nix`, with its declared source URL and the locked
rev recorded in `flake.lock` (12-char rev shown). The URL refs below are the
declared refs from `flake.nix`; they match each lock node's `original.ref`
(`nixos-unstable`, `v1.6.3`, `v5.2.1`).

| Input | Source URL | Locked rev | Follows |
| --- | --- | --- | --- |
| nixpkgs | `github:nixos/nixpkgs/nixos-unstable` | `c59305bab206` | — |
| nix-darwin | `github:LnL7/nix-darwin` | `4cff07de74b5` | nixpkgs |
| home-manager | `github:nix-community/home-manager` | `acd21c5a3420` | nixpkgs |
| disko | `github:nix-community/disko` | `725ea35e410a` | nixpkgs |
| flake-parts | `github:hercules-ci/flake-parts` | `024633cd702b` | — |
| nixos-hardware | `github:NixOS/nixos-hardware` | `0953bb1a609d` | nixpkgs |
| nixos-unified | `github:srid/nixos-unified` | `c411aafef1a2` | — |
| stasis | `github:saltnpepper97/stasis/v1.6.3` | `aa1dde4d058f` | nixpkgs, flake-parts |
| nix-index-database | `github:nix-community/nix-index-database` | `e740bc4e9d89` | nixpkgs |
| nixvim | `github:nix-community/nixvim` | `1cdfef1a6eb5` | nixpkgs, flake-parts |
| noctalia | `github:noctalia-dev/noctalia-shell/v5.2.1` | `6ef43e2bf2f3` | nixpkgs |

Inputs that follow `nixpkgs`: `nix-darwin`, `home-manager`, `disko`,
`nixos-hardware`, `stasis`, `nix-index-database`, `nixvim`, `noctalia`.
`stasis` and `nixvim` additionally follow `flake-parts`. `flake-parts` pins its
own `nixpkgs-lib` (`nix-community/nixpkgs.lib`), `nixvim` its own `systems`
(`nix-systems/default`, `future-26.11`); `nixos-unified` has no inputs.
`stasis` stays declared but no module consumes it (idle is Noctalia's,
`modules/home/idle.nix`).

**niri is NOT a flake input**: it is enabled at the system layer via the
built-in nixpkgs `programs.niri` module (`modules/nixos/gui/niri.nix`, and
`modules/nixos/console/desktop.nix` on console) and configured for Home Manager
via home-manager's built-in `wayland.windowManager.niri` module
(`modules/home/niri.nix`).

The flake is wired via `inputs.nixos-unified.lib.mkFlake` (autowiring), for systems
`x86_64-linux`, `aarch64-linux`, `aarch64-darwin`.

## Hosts

All three hosts are `x86_64-linux` NixOS configurations under
`configurations/nixos/`. `desktop` and `laptop` import
`self.nixosModules.default` + `self.nixosModules.gui` +
`inputs.disko.nixosModules.disko` plus their local
boot/hardware/graphics/power/storage modules. `console` is a hardware variant
of `desktop` (same AMD CPU/GPU, single NVMe, LUKS2/TPM2 layout): it imports
`self.nixosModules.default` + `self.nixosModules.console` (not `gui`) +
`inputs.disko.nixosModules.disko`, reuses `desktop`'s boot/hardware/power/storage
files by path, and supplies its own `graphics.nix` (no ROCm OpenCL/Ollama;
`rocmPackages.rocm-smi` only, for GPU telemetry):

| Host | Config | Hostname | Host platform | State version | Local imports |
| --- | --- | --- | --- | --- | --- |
| desktop | `configurations/nixos/desktop/default.nix` | `desktop` | `x86_64-linux` | `24.11` | `./boot.nix`, `./hardware.nix`, `./graphics.nix`, `./power.nix`, `./storage.nix` |
| laptop | `configurations/nixos/laptop/default.nix` | `laptop` | `x86_64-linux` | `24.11` | `./boot.nix`, `./hardware.nix`, `./graphics.nix`, `./power.nix`, `./storage.nix` |
| console | `configurations/nixos/console/default.nix` | `console` | `x86_64-linux` | `26.05` | `../desktop/boot.nix`, `../desktop/hardware.nix`, `../desktop/power.nix`, `../desktop/storage.nix`, `./graphics.nix` |

`configurations/home/kevin.nix` defines the shared home configuration (`me =
{ username = "kevin"; … }`, imports `self.homeModules.default`,
`home.stateVersion = "26.05"`), used by `desktop` and `laptop`.
`configurations/home/console/kevin.nix` is the console's own, smaller Home
Manager profile (`me` + `self.homeModules.{me,nix,gc,git,ssh,theme,niri,
noctalia,kitty,brave,shell,neovim,direnv,nix-index,archives}` — the theme/niri/
Noctalia/kitty modules back the desktop session from
`modules/nixos/console/desktop.nix`, `brave` carries Kevin's "basic apps" ask,
paired with the managed policy imported by `console/desktop.nix`, and
`shell`/`neovim`/`direnv`/`nix-index` give the console the same zsh/
powerlevel10k shell as desktop/laptop; still no `idle` — Noctalia's idle
behaviours (`modules/home/idle.nix`) would lock/suspend a couch session with no
keyboard at hand — and no
`packages`/`bitwarden`; `home.packages = [ nautilus ]` is the one item lifted
out of `packages`, the file manager the shared Noctalia dock pins;
`wayland.windowManager.niri.extraConfig` adds `spawn-at-startup
"opengameinstaller" "--hidden"` (concatenated with `modules/home/niri.nix`'s
own `extraConfig`), so OGI starts once per desktop session with only its tray
icon in Noctalia's bar; imports
`./heroic.nix` by relative path, a `home.activation` script that merges
`defaultSettings.addSteamShortcuts = true` into the mutable
`~/.config/heroic/config.json` at activation so games Heroic installs land in
Steam's library for Big Picture; imports `./limo.nix` by relative path,
console-only, `home.packages = [ pkgs.limo ]` plus `xdg.mimeApps.enable` and
`defaultApplications."x-scheme-handler/nxm" = "limo.desktop"` so Limo is the
default Nexus Mods `nxm://` handler for this desktop session — Nexus Mods
discontinued its own cross-platform app in January 2026, and Limo deploys
mods into the game directory itself, so no launch hook is needed for Steam,
OGI or Heroic titles; imports `./qbittorrent.nix` by relative path,
console-only, `systemd.user.services.qbittorrent-nox` running `qbittorrent-nox`
as kevin with a Nix-generated `qBittorrent.conf` copied into
`~/.local/share/qbittorrent-nox` on every start — WebUI on `127.0.0.1:8080`
with `WebUI\LocalHostAuth=false`, so OpenGameInstaller's qBittorrent client
works with no credential in the source; a user service rather than
`services.qbittorrent` because that module sets `ProtectHome`), selected via
`modules/nixos/common/myusers.nix`'s `myhome.dir` option, which the console
host sets to `self + /configurations/home/console`. The subdirectory has no
`default.nix`, so neither nixos-unified autowiring nor `myusers`'s own
directory scan (which only reads regular files) picks it up as a sibling
profile. `configurations/darwin/example.nix` is the un-wired nix-darwin
example configuration.

## Imported modules

### Home modules — `modules/home/`

`modules/home/default.nix` auto-imports every sibling entry whose name is not
`default.nix` via `attrNames (readDir ./)`; directory entries (`neovim`, `theme`)
resolve to their `default.nix`.

| Module | Purpose |
| --- | --- |
| `archives.nix` | `home.packages`: `zip`, `unzip`, `p7zip`; `xdg.mimeApps.enable` + `defaultApplications` mapping archive MIME types to `org.gnome.Nautilus.desktop` so Nautilus 50's `get_activation_action()` extracts in place on double-click with no dialog, instead of prompting; imported explicitly by `configurations/home/console/kevin.nix` since that profile has no `default.nix` and misses this directory's `readDir` autowiring |
| `bitwarden.nix` | Bitwarden vault config + `bw-ssh-pull` helper script |
| `brave.nix` | `programs.brave-origin.enable` + Bitwarden extension; activation script merges `brave.location_bar_is_wide=true` into the profile's `Preferences` (no policy exists for this pref) |
| `direnv.nix` | direnv setup (`programs.direnv` with `nix-direnv`) |
| `fastfetch.nix` | fastfetch with the NGR logo; `noctalia` fastfetch theme colored from the Nullscapes palette (`config.theme.nullscapes`) and activated via `"theme": "noctalia"` |
| `gc.nix` | Home-manager garbage collection |
| `git.nix` | Git config (`programs.git`, `lazygit`) + aliases (`g`, `lg`) |
| `idle.nix` | Noctalia's native idle behaviours via `programs.noctalia.settings.idle.behavior`: `lock` at 300 s, `screen-off` at 330 s, `lock-and-suspend` at 1800 s (`locked_timeout` 30/1500 keep the plan absolute after a lock); drives Noctalia's native lock screen; not imported by the console profile |
| `kitty.nix` | Kitty terminal config (Nullscapes palette, `background_opacity = "0.76"`) |
| `me.nix` | User config options (`me.username`, `me.fullname`, `me.email`) |
| `neovim/default.nix` | Imports nixvim home module; `programs.nixvim = import ./nixvim.nix` |
| `neovim/nixvim.nix` | nixvim configuration for neovim |
| `niri.nix` | niri compositor home config; `wayland.windowManager.niri` with `systemd.enable = false` and `portalPackage = null` (the system `programs.niri` owns units and portals), default `xwaylandSatellitePackage` (xwayland-satellite on PATH for X11 clients), default `checkConfig` (generated `config.kdl` run through `niri validate` at build); Nullscapes visual layer (blur, gradient focus ring, tab indicator, shadows, rounded corners, overview backdrop, animations, Noctalia layer rules, blurred kitty) read from `config.theme.nullscapes`; cursor from `home.pointerCursor`; keybinds incl. `noctalia msg session lock` and Noctalia shell verbs; `spawn-at-startup` of `niri-scale-4k-outputs`, an IPC helper that sets scale 2 on any output whose current mode is ≥ 3840×2160 |
| `nextcloud.nix` | Nextcloud desktop client (`services.nextcloud-client`, autostarted in background) + `home.packages` for its Nautilus/D-Bus integration files |
| `nix-index.nix` | nix-index database setup |
| `nix.nix` | Nix client settings |
| `noctalia.nix` | Noctalia V5 shell (`programs.noctalia`, systemd user service); active palette Nullscapes (`theme.custom_palette = "Nullscapes"`), `mactahoe` and `eldritch` exported as selectable custom palettes; `package` is the pinned flake build with `theme/noctalia-bar-capsule-blur.patch` applied (built from source) |
| `packages.nix` | `home.packages` list + `programs.*` (see below) |
| `shell.nix` | Shell config (zsh, p10k, eza aliases); `home.packages = [ ripgrep ]` + `programs.{eza,fzf,bat}.enable` |
| `ssh.nix` | `programs.ssh` github.com host config (SHOA-1092) |
| `theme/default.nix` | Aggregates theme modules → `./eldritch.nix`, `./mactahoe.nix`, `./nullscapes.nix` |
| `theme/eldritch.nix` | Eldritch base16 palette (SHOA-999); still exported as a Noctalia custom palette, no longer the default |
| `theme/mactahoe.nix` | Palette only: `theme.mactahoe` (vanilla MacTahoe dark/light, 16 Noctalia m* roles + `terminal`), exported as the selectable `mactahoe` Noctalia palette; sets no GTK theme |
| `theme/nullscapes.nix` | Active theme: `theme.nullscapes` palette (dark, 16 Noctalia m* roles + `terminal`) read by `noctalia.nix`, `niri.nix`, `kitty.nix`, `fastfetch.nix`; GTK `adw-gtk3-dark` (GTK 3 and 4, `colorScheme = "dark"`), icons `Papirus-Dark` (`catppuccin-papirus-folders`, mocha/lavender), cursor `catppuccin-mocha-dark-cursors` size 20, font Noto Sans 10 |
| `theme/noctalia-bar-capsule-blur.patch` | Not a module (not imported by `theme/default.nix`): noctalia-shell patch restricting the bar's blur region to its capsule backgrounds; applied by `noctalia.nix` |
| `work.nix` | Work-specific config (zsh/bash `initExtra`, e.g. macOS linker `ulimit`) |

### NixOS modules — `modules/nixos/`

| Module | Contents |
| --- | --- |
| `default.nix` | Imports `common`, `./multica.nix` and `./opencode-policy.nix`; firmware, `environment.systemPackages = [ pkgs.docker-compose pkgs.lm_sensors pkgs.pciutils pkgs.usbutils ]` (`sensors`, `lspci`, `lsusb` on every host), networkmanager, `nix.settings.experimental-features = [ "nix-command" "flakes" ]` pin, `nixpkgs.config.allowUnfree`, netbird, openssh, timezone `America/Detroit`, docker, zramSwap |
| `common/default.nix` | Imports `./myusers.nix` |
| `common/myusers.nix` | Declares the `myusers` and `myhome.dir` options and per-user top-level configuration; system-wide `programs.zsh.enable` |
| `multica.nix` | Dedicated `multica` system user (`isSystemUser`, own `multica` group, home `/var/lib/multica` created with mode `700`, `bashInteractive` shell for `sudo -u multica -H opencode auth login` / `multica login`, `extraGroups = [ "systemd-journal" "video" "render" ]` only — no `wheel`/`docker`/`libvirtd`/`networkmanager`/`i2c`, not a Nix `trusted-user`); `environment.systemPackages = [ pkgs.multica-cli pkgs.opencode pkgs.lsof pkgs.vulkan-tools pkgs.mesa-demos ]` (the last three back the operator allowlist's `lsof`, `vulkaninfo` and `eglinfo`); a `systemd.tmpfiles.settings."10-multica-games"` `A+` rule granting `u:multica:rX,d:u:multica:rX` recursively on `/home/kevin/UGI_Games` (no entry on `/home/kevin` itself, absent hosts skipped); `systemd.services.multica-daemon` (`multica daemon start --foreground` as `User`/`Group` `multica`, `wantedBy multi-user.target`, after/wants `network-online.target`, `ConditionPathExists` on `/var/lib/multica/.multica/config.json` so it stays inert before `multica login`, `Restart = "on-failure"`, `RestartSec = 10`; environment `HOME`, `MULTICA_DAEMON_AUTO_UPDATE=false`, `MULTICA_SERVER_URL=https://multica-api.panic.ac` (outranks `config.json`'s `server_url`; the documented on-host login repeats it as `--server-url`), `MULTICA_OPENCODE_PATH` pinned to the opencode build, `MULTICA_CLAUDE_PATH`/`MULTICA_CODEX_PATH` pinned to a non-existent path so only opencode is exposed, `MULTICA_WORKSPACES_ROOT=/var/lib/multica/multica_workspaces`, `PATH=/run/wrappers/bin:/run/current-system/sw/bin` with `enableDefaultPath = false`; hardening `NoNewPrivileges`, `ProtectHome = "tmpfs"` with `BindReadOnlyPaths = [ "-/home/kevin/UGI_Games" ]` (the game library is the only path under `/home` the unit sees, read-only; skipped where it does not exist), `PrivateTmp`, `ProtectKernelTunables`, `RestrictSUIDSGID`, `ProtectSystem = "strict"` with `ReadWritePaths` the home only). Reaches desktop, laptop and console through `default.nix`; no credential declared. Also exposed as `nixosModules.multica` by nixos-unified autowiring |
| `opencode-policy.nix` | opencode managed config `environment.etc."opencode/opencode.json"`, reaching desktop, laptop and console through `default.nix` (not darwin: `modules/darwin/common` links only `common/`). Top level only `$schema`, `share = "disabled"`, `autoupdate = false` and `agent.multica-operator` (`mode = "primary"`, `disable = false`, `model = "deepseek/deepseek-flash"`, a read-only diagnostics `prompt`, and a `permission` block: `bash` `"*": "deny"` then an allowlist of read-only commands as `X` and `X *` — unit, session, journal, network, process (`ps`, `pgrep`, `top -b -n1`, `lsof`), kernel (`dmesg`, `lsmod`, `modinfo`, `lscpu`, `systemd-analyze time`/`blame`/`critical-chain`/`security`/`cat-config`, `coredumpctl list`/`info`), hardware and graphics (`vulkaninfo`, `eglinfo`, `nvidia-smi`, `rocm-smi`), Flatpak (`list`/`info`/`ps`/`remotes`/`history`), `nix-store --query`/`-q` and file inspection (`du`, `findmnt`, `getfacl`, `which` alongside `ls`/`cat`/`grep`/…) — then trailing denies for redirection, command substitution, `--option`, `--attachment`, URLs, the multica CLI's `--server-url`/`--profile`/`--workspace-id`, Nix `--store`/`--eval-store`/substituters, `systemctl`/`loginctl`/`systemd-analyze` `-H`/`--host`, the `ss` filter, `lspci` `-q`/`-Q`/`-O` and `lsof` `@host` forms that resolve an agent-chosen name over DNS, `vulkaninfo -o`/`--output`, and `dmesg` clear/console flags (model guidance: opencode matches the unquoted command text, so quoting defeats these); no `nix path-info`, `nix log` or `nix why-depends`, which evaluate flakerefs or realise their installables; `edit` denied except the `multica` user's `multica_workspaces`, and within it denied for `opencode.json(c)`, `.opencode/` and `AGENTS.md`; `read`/`external_directory` `"*": "deny"`, allow system paths, `/home/kevin/UGI_Games` and below, and the workspaces, then deny secret paths in `~/`, absolute and `/`-relative forms; `webfetch`/`websearch`/`task`/`question` denied), selected by the Multica agent's `--agent multica-operator`. Advisory against a process that owns its workspace root: the `multica` user in `multica.nix` is the boundary. Rendered by a local ordered-object renderer instead of `builtins.toJSON` (which sorts keys) because opencode applies the last matching rule in file order. No provider key: `opencode auth login` stays imperative. Also exposed as `nixosModules.opencode-policy` by nixos-unified autowiring |
| `gui/default.nix` | Imports `./brave.nix`, `./flatpak.nix`, `./niri.nix`; boot console/quiet/plymouth settings, `services.xserver.enable` |
| `gui/brave.nix` | Managed Brave policy (`environment.etc."brave/policies/managed/policies.json"`), incl. default search provider (Brave Search), force-pinned Bitwarden toolbar entry, and a `3rdparty.extensions` block presetting Bitwarden's managed-storage environment to `vault.panic.ac` (fresh installs only) |
| `gui/flatpak.nix` | Bazaar (`pkgs.bazaar`) plus a `flatpak-remotes` oneshot registering the `flathub` and `flathub-beta` system remotes it shows |
| `gui/niri.nix` | Noctalia greeter display manager (cursor `catppuccin-mocha-dark-cursors`), `programs.niri.enable`, `services.flatpak.enable`, Steam, fonts, Grayjay flatpak service, `NAUTILUS_4_EXTENSION_DIR` session variable (nautilus-python, for the Nextcloud client's Nautilus integration) |
| `console/default.nix` | Imports `./session.nix`, `./performance.nix`, `./input.nix`, `./launchers.nix`, `./streaming.nix`, `./desktop.nix`, `./cec.nix`, `./rgb.nix`, `./power.nix`, `./steamos-manager.nix`; boot quiet/plymouth settings (no `services.xserver.enable` — gamescope needs no X server stack). Console-only: reaches neither desktop nor laptop |
| `console/session.nix` | `programs.gamescope.capSysNice`, `programs.gamescope.enableWsi` (the Gamescope WSI Vulkan layer, the client-side path for HDR swapchains), `programs.steam` (incl. `gamescopeSession.enable`, `gamescopeSession.args = [ "--mangoapp" "--hdr-enabled" "--adaptive-sync" ]` — HDR10 output and VRR requested from gamescope, the ChimeraOS `gamescope-session-plus` opt-ins, since the GPU drives the HDR/VRR-capable TV directly; SDR content shows at gamescope's default 400 nits, inverse tone mapping off — `gamescopeSession.env = { ENABLE_HDR_WSI = "1"; DXVK_HDR = "1"; }` (the client-side pair ChimeraOS exports with `--hdr-enabled`), `gamescopeSession.steamArgs = [ "-gamepadui" "-steamos3" "-steampal" "-steamdeck" "-pipewire-dmabuf" ]` — the full SteamOS gaming-mode flag set Valve/ChimeraOS/Bazzite all use, replacing the nixpkgs default's desktop-Big-Picture `-tenfoot`; `-steamos3` is what makes Steam's "Switch to Desktop" call `steamos-session-select` at all, `protontricks.enable`, `extraPackages = [ steamos-session-select ]`), `services.greetd` autologin into `console-session` (a loop that reads Steam's "Switch to Desktop" request and starts either `steam-gamescope` or the niri/Noctalia session from `./desktop.nix` — launched through `niri-session` from `programs.niri.package`, which runs `niri.service` and returns once niri has quit; the "Return to Gaming Mode" path ends it with `niri msg action quit --skip-confirmation` when `NIRI_SOCKET` is set — falling back to `tuigreet` when neither is requested), `services.pipewire`/`security.rtkit`, bluetooth (with `hardware.bluetooth.settings` carrying SteamOS's BlueZ `main.conf` tuning from Jovian: `General.MultiProfile`/`FastConnectable`/`KernelExperimental`, `LE.ScanIntervalSuspend`/`ScanWindowSuspend`)/flatpak/polkit/dconf. `console-session` runs `systemctl --user start steamos-manager.service` (the user daemon from `./steamos-manager.nix`, whose unit is bound to `graphical-session.target` that the gamescope session never reaches; failure tolerated) and then `steam-tweaks` (`./launchers.nix`) immediately before `steam-gamescope` on every loop iteration, re-asserting Steam's declared compat-tool mappings and launch options while Steam is guaranteed not running; it also starts `steam-notif-daemon.service` (callpackaged `packages/steam-notif-daemon.nix`; `systemd.user.services.steam-notif-daemon`, `Restart=on-failure`, no `wantedBy`) right before `steam-gamescope` and stops it right after, so the daemon owns `org.freedesktop.Notifications` only while gamescope runs (Noctalia owns it in the niri session) |
| `console/performance.nix` | CachyOS-style tuning: `services.scx` (`scx_lavd`), `services.ananicy` (`ananicy-cpp` + `ananicy-rules-cachyos`), `programs.gamemode`, `vm.max_map_count` sysctl, `vm.mmap_rnd_bits = 28` (NixOS's `55-nixos-aslr-entropy.conf` sets the kernel maximum, 32; at 32 Proton's inherited seccomp filter kills `wine64-preloader` children with SIGSYS), `boot.kernelModules = [ "ntsync" ]` + udev uaccess rule. No `services.lact` on the console: steamos-manager (`./steamos-manager.nix`) owns the amdgpu sysfs knobs there and lactd would re-apply its own profile over Steam's settings (the desktop keeps LACT in `configurations/nixos/desktop/graphics.nix`) |
| `console/input.nix` | `hardware.xone.enable`, `hardware.xpadneo.enable` (Xbox controllers, dongle + Bluetooth), `services.udev.packages = [ pkgs.game-devices-udev-rules ]`, `hardware.uinput.enable` |
| `console/launchers.nix` | `environment.systemPackages`: `heroic`, `protonup-qt`, `mangohud`, `lutris`, `umu-launcher`, callpackaged `opengameinstaller`, `bun` (OGI's NixOS branch expects Bun on PATH and offers no installer), `unrarFatboy` (a `writeShellApplication` named `unrar` wrapping `pkgs.unrar`; reports success when fatboy-unpack's per-volume `unrar x … -idn -kb -y` call exits 6 with unrar's 'start extraction from a previous volume' warning, transparent otherwise), `python3` (interpreter for the umu zipapp OGI downloads under `~/.local/share/OpenGameInstaller/bin/umu/` — OGI's own game flow now resolves `umu-run` through `OGI_UMU_RUN`, which points at the nixpkgs `umu-launcher` above (see `packages/opengameinstaller.nix`), but `python3` stays here for any community addon that still spawns the zipapp path directly); `protonCachyosUserSettings` (`{ PROTON_FSR4_UPGRADE = "1"; }`, hoisted to its own `let` binding — the one source of truth for this dict) passed as callpackaged `protonCachyos`'s (`packages/proton-cachyos-bin.nix`) `userSettings` argument — the FSR 4 upgrade on by default for every game run through the store tool, via that package's `user_settings.py` mechanism; per-game launch environment overrides it — sets `environment.sessionVariables.PROTONPATH` to its `steamcompattool` output (the umu/OGI default Proton, since OGI spreads `process.env` into every `umu-run` it spawns and only overrides `PROTONPATH` per game) and is added to `programs.steam.extraCompatPackages` (merges with `session.nix`'s `proton-ge-bin`); `steamTweaks` (attrset: `compatToolMapping` — appid to compat-tool name, `"0"` = `protonCachyos.steamDisplayName` — `launchOptions` — appid to launch-options string, empty by default — and `protonCachyosUserSettings` — the same binding above, reaching the JSON so the embedded Python can apply it to other Proton-CachyOS copies) rendered to `steamTweaksJson` via `writeText`/`builtins.toJSON`, applied by `steamTweaksApply` (`writeShellApplication` named `steam-tweaks`, `python3.withPackages (ps: [ ps.vdf ])`) — the ChimeraOS `steam-tweaks`/`chimera_app/steam_config.py` model rendered from Nix instead of their downloaded YAML tweaks database (that database is deliberately not adopted: it is tuned for ChimeraOS's own Proton set and would override Proton-CachyOS per title, and pulling a moving remote file at session start is the opposite of declarative); writes `CompatToolMapping` entries into `config/config.vdf` (creating the `InstallConfigStore.Software.Valve.Steam` skeleton if the file does not exist yet) and `LaunchOptions` into every `userdata/<id>/config/localconfig.vdf`, tolerating both `Valve`/`valve` and `Steam`/`steam` key casing, idempotent (skips the write and log line when nothing changed), skipping entirely while Steam is running; also refuses to write, and removes any existing, `CompatToolMapping` entry for a Steam Linux Runtime app id (`RUNTIME_APPIDS`: scout/soldier/sniper/4.0/steamrt4-arm64), `repair_runtimes` deletes a runtime's install tree, `downloading/` entry and manifest when its `appmanifest_<appid>.acf` is `StateFlags 4` but zeroed (`buildid`/`SizeOnDisk` `0` or missing, or no `InstalledDepots`), only under `steamapps` in the main Steam library, so Steam offers it for reinstall from Library → Tools again (ValveSoftware/steam-for-linux#13248, #13199), and `sync_proton_cachyos_defaults` writes the same `user_settings.py` `protonCachyos` gets into every `compatibilitytools.d/proton-cachyos-*-slr*` directory (case-insensitive, symlinks followed, a `proton` file required) that OGI's `auto` picker or Steam's own picker could select instead of the store tool — a fixed marker line lets a rewrite tell "ours, stale" from a user's own file (left alone, one stderr line), and any write error (a read-only directory, for example) is logged and skipped rather than aborting the rest of the script; called from `console-session` (`./session.nix`) before `steam-gamescope`; `systemd.services.chromium-flatpak` installs/updates `org.chromium.Chromium` from Flathub for OGI's genesis-lib addon, mirroring `gui/niri.nix`'s `grayjay-flatpak` |
| `console/streaming.nix` | `services.sunshine` (`enable`, `capSysAdmin`, `openFirewall`, `autoStart`) |
| `console/rgb.nix` | `systemd.services.rgb-off` (`Type=oneshot`, `StateDirectory=rgb-off`): switches off the ASUS Aura USB motherboard/fan-header RGB controller (`0b05:19af`) as a client of the OpenRGB server the console already runs (`services.hardware.openrgb` from `configurations/nixos/desktop/hardware.nix`; `wants`/`after` `openrgb.service`, uses `services.hardware.openrgb.package`). A `writeShellApplication` runs `openrgb --config $STATE_DIRECTORY --nodetect --device "TUF GAMING B850M-PLUS WIFI" --mode off` (the controller is named "ASUS " + DMI `board_name`), retrying every 2s up to 30 times while the server is not yet listening or has not detected the controller. `wantedBy` `multi-user.target` and `after`/`wantedBy` the same sleep targets as `./cec.nix`, so it runs at boot and after every resume. Asserts the server is enabled on its default port 6742. Never detects hardware itself and never touches another controller |
| `console/cec.nix` | HDMI-CEC one-touch-play and TV standby over a Pulse-Eight USB-CEC adapter (`pkgs.libcec`'s `cec-client`), modelled on Bazzite's `cec-onboot`/`cec-onsleep`/`cec-onpoweroff`: `cec-onboot` (turns the TV on and sets active source) runs on boot/hotplug via a `services.udev.extraRules` `SYSTEMD_WANTS` rule and on resume via `wantedBy` on the sleep targets; `cec-onsleep`/`cec-onpoweroff` first run `am 0` (turn off the adapter's EEPROM-stored autonomous mode, which libcec documents as what lets the TV/CEC bus wake the host) and then put the TV on standby `before` suspend/hibernate/poweroff; a second udev rule also disables the adapter's own USB remote wakeup, leaving the keyboard, the xone dongle (already armed by its own driver) and the power button as the wake paths |
| `console/power.nix` | `services.logind.settings.Login = { HandlePowerKey = "suspend"; HandlePowerKeyLongPress = "poweroff"; }` — physical power button suspends to RAM (game stays in memory), ~5s hold powers off; modelled on ChimeraOS's `power_off.conf` (generic, non-Deck hardware). Steam's own SteamOS "Suspend" menu item and CEC/controller-wake are already handled by `./session.nix`'s gamescope args and `./cec.nix`/`./input.nix` respectively; no `powerbuttond` (Deck-only, not in nixpkgs) |
| `console/steamos-manager.nix` | Valve's `steamos-manager` (callpackaged `packages/steamos-manager.nix`) behind Steam's Quick Access "Performance" tab: `services.dbus.packages` (system-bus policy/activation and session-bus activation files), `environment.systemPackages` (`steamosctl`), `systemd.services.steamos-manager` (root daemon, `steamos-manager -r --device-config <toml>`, `Type=notify-reload`, `BusName=com.steampowered.SteamOSManager1`, upstream's restart/start-limit values, `wantedBy multi-user.target`) and `systemd.user.services.steamos-manager` (user daemon, same flag without `-r`, `wantedBy graphical-session.target`; started by hand from `console-session` for the gamescope session). `--device-config` bypasses upstream's exact-match DMI device lookup (no upstream config matches this board and there is no generic fallback); the forced TOML (`writeText`) carries `[gpu_performance] driver = "amdgpu"` and `[gpu_power_profile] driver = "amdgpu"` only — `GpuPerformanceLevel1`/`GpuPowerProfile1` over `power_dpm_force_performance_level`, `pp_power_profile_mode`, `pp_dpm_sclk`, `pp_od_clk_voltage` (the overdrive mask from `configurations/nixos/desktop/hardware.nix`), plus the unconfigured `CpuScaling1` (cpufreq governor) and `CpuScheduler1` (starts/stops `scx.service`, the unit `./performance.nix`'s `services.scx` declares). `[tdp_limit]` deliberately absent: `TdpLimit1` needs a `[tdp_limit.range]` the daemon never derives from the card, so it waits for the console's `power1_cap_min/max/default` readings |
| `console/desktop.nix` | Imports `../gui/brave.nix` (standalone `environment.etc` entry, carries Brave's managed policy without the rest of `gui/`) and `../gui/flatpak.nix` (Bazaar + the `flatpak-remotes` oneshot; `services.flatpak.enable` is already on via `./session.nix`); `programs.niri.enable`, `services.gvfs`/`services.udisks2` (for the console profile's nautilus), `environment.pathsToLink`, `fonts.packages` (Noctalia's icon/text fonts, copied from `gui/niri.nix`) — a console-only copy, not an import, of `gui/niri.nix`'s system layer; deliberately omits `services.displayManager.noctalia-greeter` (would double-define `services.greetd.settings.default_session` against `./session.nix`), Grayjay, kdeconnect, an explicit gnome-keyring (`programs.niri` still defaults it on) and `services.xserver.enable` |

### Darwin modules — `modules/darwin/`

| Module | Contents |
| --- | --- |
| `default.nix` | nix-darwin configuration (TouchID sudo, macOS dock/finder defaults) |
| `common` | Symlink to `../nixos/common` (shared myusers / zsh / home-manager wiring) |

### Flake modules — `modules/flake/`

| Module | Purpose |
| --- | --- |
| `activate-home.nix` | `nix run` activate-home app when no NixOS configurations are wired |
| `devshell.nix` | Default dev shell (`just`, `nixd`) |
| `neovim.nix` | Packages neovim built from `../home/neovim/nixvim.nix` via nixvim |
| `template.nix` | `nix flake init` templates |
| `toplevel.nix` | Imports nixos-unified flake modules (default + autoWire); formatter `nixpkgs-fmt` |

## Installed package sets

### `home.packages` (from `modules/home/packages.nix`, Desktop applications block incl. Telegram + Signal)

| Group | Packages |
| --- | --- |
| General | `omnix`, `opencode` |
| Desktop applications | `bitwarden-desktop`, `bolt-launcher`, `ente-auth`, `firefox`, `github-desktop`, `gnome-calendar`, `gnome-disk-utility`, `lmstudio`, `looking-glass-client`, `mission-center`, `nautilus`, `obsidian`, `netbird-ui`, `paperweight`, `papers`, `proton-authenticator`, `proton-pass`, `proton-vpn`, `protonmail-bridge-gui`, `protonmail-desktop`, `runelite`, `signal-desktop`, `telegram-desktop`, `discord.override { withVencord = true; }`, `vscodium` |
| Unix tools | `age`, `ansible`, `bitwarden-cli`, `cloudflared`, `crane`, `fluxcd`, `gh`, `go-task`, `helmfile`, `kubeconform`, `kubecolor`, `kubectl`, `kubernetes-helm`, `kustomize`, `minijinja`, `mise`, `ranger`, `fd`, `sd`, `sops`, `stern`, `talhelper`, `talosctl`, `terraform`, `tree`, `gnumake`, `yamllint`, `yq-go`, `proton-pass-cli`, `_1password-cli` |
| Nix dev | `cachix`, `nil`, `nix-info`, `nixpkgs-fmt` |
| Other | `less` (man pager) |

### `programs.*` enabled in `modules/home/packages.nix`

`jq`, `btop` (both `enable = true`). `bat`, `fzf`, `eza` moved to
`modules/home/shell.nix`, along with `ripgrep` (`home.packages`), so the
console's `shell` import gets the tools its aliases need.

`modules/home/fastfetch.nix` additionally adds `home.packages = [ pkgs.fastfetch ]`.

### System packages

`environment.systemPackages = [ pkgs.docker-compose pkgs.lm_sensors pkgs.pciutils
pkgs.usbutils ]` in `modules/nixos/default.nix` and `[ pkgs.multica-cli
pkgs.opencode pkgs.lsof pkgs.vulkan-tools pkgs.mesa-demos ]` in
`modules/nixos/multica.nix`, on every NixOS host; everything
else is installed per-user via home-manager or by a host profile's own modules.

## Repo-local packages — `packages/`

| Package | File | Notes |
| --- | --- | --- |
| paperweight | `packages/paperweight.nix` | Callpackaged in `modules/home/packages.nix` |
| mactahoe-gtk-theme | `packages/mactahoe-gtk-theme.nix` | MacTahoe-Dark GTK theme, `tint` argument (defaults are the vanilla MacTahoe values); flake package only, consumed by no module since the active GTK theme is Nullscapes' `adw-gtk3-dark` |
| wallpapers | `packages/wallpapers.nix` | Wallpaper collection (SHOA-1058, `packages/wallpapers/assets/`); consumed by `modules/home/noctalia.nix` |
| opengameinstaller | `packages/opengameinstaller.nix` | OpenGameInstaller front-end, built from the `shockstruck/OpenGameInstaller` fork's `v4.3.1-ss.17` release (fork of `Nat3z/OpenGameInstaller`, same `Build/release` AppImage): AppImage unpacked with `appimageTools.extract`, its `resources/app.asar` run on nixpkgs `electron_42` (the bundled 40.10.2 is EOL in nixpkgs; the asar's native modules are all N-API, so the major is free) with no bubblewrap sandbox — needed for OGI's own Play button (pressure-vessel via `umu-run`), since Steam-managed shortcuts no longer route through OGI at launch as of ss.1 (OGI writes the launch environment into the shortcut's `LaunchOptions` and Steam starts the game directly); wrapper execs `systemd-cat -t opengameinstaller --stderr-priority=warning` in front of `electron`, so OGI's stdout/stderr (including `[umu]` lines) land in the journal instead of vanishing when the process is launched from a `.desktop` entry or Steam shortcut — read them with `journalctl -t opengameinstaller`, this package's replacement for the `update/latest.log` the upstream `-Setup.AppImage` would have produced and which this package deliberately does not ship; wrapper also sets `ELECTRON_FORCE_IS_PACKAGED=1` (keeps `app.isPackaged` true on a bare `electron` binary), `APPIMAGE=/run/current-system/sw/bin/opengameinstaller` so OGI's per-game `.desktop` entries (`Exec=<launcher> --game-id=N`) and the Steam re-sync's legacy-executable match still resolve the launcher (Steam shortcuts themselves no longer exec it on Linux), and (as of ss.9) `OGI_UMU_RUN` to `lib.getExe umu-launcher` (the nixpkgs package above) so OGI's Play button and redistributable installer resolve `umu-run` through nixpkgs' FHS-wrapped `steam.buildRuntimeEnv` instead of the upstream umu zipapp OGI downloads, whose pressure-vessel is a generic-Linux dynamically linked binary NixOS refuses to exec; as of ss.12, a game's settings also expose a "Redistributables" repair action (recorded redistributables plus an allowlisted set of common winetricks runtimes, reinstalled into the existing prefix without migrating or touching the Steam shortcut) — routed through the same `OGI_UMU_RUN`-resolved `umu-run`, so no change to this package was needed; as of ss.14, OGI's startup migrations rewrite a stored SteamRip or Fatboy unpack addon entry from `gitlab.com/fat-addons/*` to the ShockStruck forks (`github.com/shockstruck/steamrip-addon`, `github.com/shockstruck/fatboy-unpack`) and reinstall them — addons are runtime user config, so this package pins no addon; as of ss.15, OGI's compat-tool listing (its `auto` Steam-shortcut compat tool and the per-game Proton picker) also scans the tool directories named by `PROTONPATH` and `STEAM_EXTRA_COMPAT_TOOLS_PATHS` and follows symlinked tool directories, so that `auto` can resolve to the store Proton-CachyOS from `console/launchers.nix` when OGI's environment carries those variables (FSR 4 does not depend on it: `steam-tweaks` also seeds every ProtonUp-Qt Proton-CachyOS copy); as of ss.16, a WebTorrent download stages in a visible `<Game>/torrent/` (an existing hidden `.torrent` staging directory is still reused) and setup no longer moves it into `old_files`, and a seeding torrent card gets a Stop seeding action; as of ss.17, OGI's startup migrations add the DODI Repacks addon (`github.com/shockstruck/dodi-addon`) to the addons list when no entry already names it and install it, repairing an entry that is configured but was never cloned — still runtime user config, so this package pins no addon; callpackaged in `modules/nixos/console/launchers.nix` |
| steamos-manager | `packages/steamos-manager.nix` | Valve's SteamOS Manager daemon (`gitlab.steamos.cloud/holo/steamos-manager` `v26.4.1`, `fetchFromGitLab`), `rustPlatform.buildRustPackage` with `cargoLock.lockFile = ./steamos-manager/Cargo.lock` — upstream's lock vendored byte-identical beside the package (all crates.io, no git deps) instead of a `cargoHash`; `doCheck = false` (tests assume Deck hardware and FHS paths); patches `packages/steamos-manager/hardcode-paths.patch` (Jovian-NixOS's, trimmed to the store-path hunks for the daemon's data dirs, D-Bus activation stubs, `dmidecode`, `scx_lavd` (`scx.full`), `iw`/`iwd`/`trace-cmd`, applied through `replaceVars`) and `disable-ftrace.patch` (Jovian's, verbatim: the root daemon's ftrace relay to the absent `steamos-log-submitter`); build inputs mirror Jovian's (`glib`, `pkg-config`, `bindgenHook`, `wrapGAppsNoGuiHook` / `glib`, `gsettings-desktop-schemas`, `speechd-minimal`, `udev`); `postInstall` copies the D-Bus system service/policy, session service and interface XML files, `data/devices/*.toml` and `data/platform.toml` (Deck-only script paths that fail upstream's `is_valid` check and stay off the bus); systemd units are not installed — `modules/nixos/console/steamos-manager.nix` declares them; MIT; `mainProgram = "steamosctl"`; tracked by the weekly `nix-update` pass like the other packages (re-check the patches after a bump) |
| proton-cachyos-bin | `packages/proton-cachyos-bin.nix` | CachyOS's Proton fork (FSR 4 / OptiScaler auto-injection); not in nixpkgs, fetches upstream's prebuilt `-slr` release tarball (`x86_64_v3` asset) via `fetchurl`, `outputs = [ "out" "steamcompattool" ]` in the `proton-ge-bin` shape, `dontConfigure`/`dontBuild`/`dontFixup` (fixup would corrupt the Wine binaries and pressure-vessel scripts), `compatibilitytool.vdf` renamed to the stable display name held in `steamDisplayName` (hoisted to `let`, exposed as `passthru.steamDisplayName` so consumers do not repeat the literal — mirrors nixpkgs `proton-ge-bin`) across version bumps; `userSettings` argument (attrset of string to string, default `{ }`) is written via `writeText` into `$steamcompattool/user_settings.py`, Proton's own tool-level defaults mechanism (`proton`'s `init_session` applies each entry only when the launch environment does not already set it) — so a caller can default env vars for every game run through this tool without touching the session; `passthru.nixUpdateArgs = [ "--version-regex" "cachyos-(.+)-slr" ]` lets `.github/workflows/update-flake-lock.yaml`'s daily "Update packaged apps" step bump `version`/`hash` automatically, since CachyOS's release tags (`cachyos-<version>-slr`) aren't a bare version `nix-update` can infer on its own; callpackaged in `modules/nixos/console/launchers.nix`, which points `environment.sessionVariables.PROTONPATH` at its `steamcompattool` output, sets `userSettings = { PROTON_FSR4_UPGRADE = "1"; }`, and adds it to `programs.steam.extraCompatPackages` |
| steam-notif-daemon | `packages/steam-notif-daemon.nix` | Jovian-Experiments' `steam_notif_daemon` `v1.0.1` (`fetchFromGitHub`, `meson`/`ninja`/`pkg-config`, `systemd` + `curl`, `-Dsd-bus-provider=libsystemd`): a minimal `org.freedesktop.Notifications` server forwarding other applications' XDG notifications into Steam's overlay via `steam://open_xdg_notification/…` (not Steam's own toasts); `packages/steam-notif-daemon/handler.patch` is Jovian's `jovian.patch` verbatim, applied through `replaceVars` to point the hard-coded Steam path at a `writeShellScript` handler running `~/.steam/root/ubuntu12_32/steam` in the `steamRun` FHS env passed by `console/session.nix` (`programs.steam.package.run`), falling back to `steam-run` from `PATH` when the argument is unset; MIT; `mainProgram = "steam_notif_daemon"`; run by `modules/nixos/console/session.nix` around `steam-gamescope` |
