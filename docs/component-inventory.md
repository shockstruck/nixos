# Component inventory

Captured against `origin/main` @ `7bba16c` (2026-09-14). This doc is not
imported by the flake and does not affect the build; it is a living inventory
that must be re-verified against `main` whenever the flake changes.

## Flake inputs

Every top-level input of `flake.nix`, with its declared source URL and the locked
rev recorded in `flake.lock` (12-char rev shown). The lockfile records revs only —
no `ref` fields are captured — so the URL refs below are the declared refs from
`flake.nix`.

| Input | Source URL | Locked rev | Follows |
| --- | --- | --- | --- |
| nixpkgs | `github:nixos/nixpkgs/nixos-unstable` | `ef34387ddd75` | — |
| nix-darwin | `github:LnL7/nix-darwin` | `4cff07de74b5` | nixpkgs |
| home-manager | `github:nix-community/home-manager` | `cfcda3f99334` | nixpkgs |
| disko | `github:nix-community/disko` | `ff8702b4de27` | nixpkgs |
| flake-parts | `github:hercules-ci/flake-parts` | `31729ca8cbdb` | — |
| nixos-hardware | `github:NixOS/nixos-hardware` | `24cfdc1f9344` | nixpkgs |
| nixos-unified | `github:srid/nixos-unified` | `c411aafef1a2` | — |
| stasis | `github:saltnpepper97/stasis/v1.6.3` | `aa1dde4d058f` | nixpkgs, flake-parts |
| nix-index-database | `github:nix-community/nix-index-database` | `a74e17340755` | nixpkgs |
| nixvim | `github:nix-community/nixvim` | `afcfb8c1dc07` | nixpkgs, flake-parts |
| noctalia | `github:noctalia-dev/noctalia-shell/v5.1.0` | `c7b9197af77f` | nixpkgs |

Inputs that follow `nixpkgs`: `nix-darwin`, `home-manager`, `disko`,
`nixos-hardware`, `stasis`, `nix-index-database`, `nixvim`, `noctalia`.
`stasis` and `nixvim` additionally follow `flake-parts`. `flake-parts` (via its
own `nixpkgs-lib`) and `nixos-unified` pin their own nixpkgs.

**Hyprland is NOT a flake input** (SHOA-1037, reverting the SHOA-997 compositor
swap): it is enabled at the system layer via the built-in nixpkgs
`programs.hyprland` module (`modules/nixos/gui/hyprland.nix`) and configured for
Home Manager via the built-in `wayland.windowManager.hyprland` module
(`modules/home/hyprland.nix`). The previous compositor flake input is gone.

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
files by path, and supplies its own `graphics.nix` (no ROCm/OpenCL/Ollama):

| Host | Config | Hostname | Host platform | State version | Local imports |
| --- | --- | --- | --- | --- | --- |
| desktop | `configurations/nixos/desktop/default.nix` | `desktop` | `x86_64-linux` | `24.11` | `./boot.nix`, `./hardware.nix`, `./graphics.nix`, `./power.nix`, `./storage.nix` |
| laptop | `configurations/nixos/laptop/default.nix` | `laptop` | `x86_64-linux` | `24.11` | `./boot.nix`, `./hardware.nix`, `./graphics.nix`, `./power.nix`, `./storage.nix` |
| console | `configurations/nixos/console/default.nix` | `console` | `x86_64-linux` | `26.05` | `../desktop/boot.nix`, `../desktop/hardware.nix`, `../desktop/power.nix`, `../desktop/storage.nix`, `./graphics.nix` |

`configurations/home/kevin.nix` defines the shared home configuration (`me =
{ username = "kevin"; … }`, imports `self.homeModules.default`,
`home.stateVersion = "26.05"`), used by `desktop` and `laptop`.
`configurations/home/console/kevin.nix` is the console's own, smaller Home
Manager profile (`me` + `self.homeModules.{me,nix,gc,git,ssh,theme,hyprland,
noctalia,kitty,brave,shell,neovim,direnv,nix-index}` — the theme/Hyprland/
Noctalia/kitty modules back the desktop session from
`modules/nixos/console/desktop.nix`, `brave` carries Kevin's "basic apps" ask,
paired with the managed policy imported by `console/desktop.nix`, and
`shell`/`neovim`/`direnv`/`nix-index` give the console the same zsh/
powerlevel10k shell as desktop/laptop; still no `idle` — hypridle would
lock/suspend a couch session with no keyboard at hand — and no
`packages`/`bitwarden`; `home.packages = [ nautilus ]` is the one item lifted
out of `packages`, the file manager the shared Noctalia dock pins; imports
`./heroic.nix` by relative path, a `home.activation` script that merges
`defaultSettings.addSteamShortcuts = true` into the mutable
`~/.config/heroic/config.json` at activation so games Heroic installs land in
Steam's library for Big Picture; and `./opengameinstaller.nix`, a
`wayland.windowManager.hyprland.settings.window_rule` that force-tiles OGI's
window (`class` matching `opengameinstaller(-gui)?` case-insensitively) since
OGI's non-resizable main window otherwise floats over the tiled layout),
selected via
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
| `bitwarden.nix` | Bitwarden vault config + `bw-ssh-pull` helper script |
| `brave.nix` | `programs.brave-origin.enable` + Bitwarden extension; activation script merges `brave.location_bar_is_wide=true` into the profile's `Preferences` (no policy exists for this pref) |
| `direnv.nix` | direnv setup (`programs.direnv` with `nix-direnv`) |
| `fastfetch.nix` | fastfetch with the Noctalia theme + NGR logo (SHOA-1058) |
| `gc.nix` | Home-manager garbage collection |
| `git.nix` | Git config (`programs.git`, `lazygit`) + aliases (`g`, `lg`) |
| `hyprland.nix` | Hyprland compositor home config (SHOA-1037); `wayland.windowManager.hyprland`, pointer cursor, keybinds incl. `noctalia msg session lock` |
| `idle.nix` | Idle management via `services.hypridle` (hypridle from nixpkgs); drives Noctalia's native lock screen |
| `kitty.nix` | Kitty terminal config (founder palette) |
| `me.nix` | User config options (`me.username`, `me.fullname`, `me.email`) |
| `neovim/default.nix` | Imports nixvim home module; `programs.nixvim = import ./nixvim.nix` |
| `neovim/nixvim.nix` | nixvim configuration for neovim |
| `nextcloud.nix` | Nextcloud desktop client (`services.nextcloud-client`, autostarted in background) + `home.packages` for its Nautilus/D-Bus integration files |
| `nix-index.nix` | nix-index database setup |
| `nix.nix` | Nix client settings |
| `noctalia.nix` | Noctalia V5 shell (`programs.noctalia`, systemd user service, founder palette) |
| `packages.nix` | `home.packages` list + `programs.*` (see below) |
| `shell.nix` | Shell config (zsh, p10k, eza aliases); `home.packages = [ ripgrep ]` + `programs.{eza,fzf,bat}.enable` |
| `ssh.nix` | `programs.ssh` github.com host config (SHOA-1092) |
| `theme/default.nix` | Aggregates theme modules → `./eldritch.nix`, `./founder.nix`, `./mactahoe.nix` |
| `theme/eldritch.nix` | Eldritch base16 palette (SHOA-999); still exported as a Noctalia custom palette, no longer the default |
| `theme/founder.nix` | Founder palette (SHOA-1094); single source of truth for theme colors |
| `theme/mactahoe.nix` | MacTahoe-Dark GTK theme tinted from the founder palette (SHOA-1094) |
| `work.nix` | Work-specific config (zsh/bash `initExtra`, e.g. macOS linker `ulimit`) |

### NixOS modules — `modules/nixos/`

| Module | Contents |
| --- | --- |
| `default.nix` | Imports `common`; firmware, `environment.systemPackages = [ pkgs.docker-compose ]`, networkmanager, `nix.settings.experimental-features = [ "nix-command" "flakes" ]` pin, `nixpkgs.config.allowUnfree`, netbird, openssh, timezone `America/Detroit`, docker, zramSwap |
| `common/default.nix` | Imports `./myusers.nix` |
| `common/myusers.nix` | Declares the `myusers` and `myhome.dir` options and per-user top-level configuration; system-wide `programs.zsh.enable` |
| `gui/default.nix` | Imports `./brave.nix`, `./flatpak.nix`, `./hyprland.nix`; boot console/quiet/plymouth settings, `services.xserver.enable` |
| `gui/brave.nix` | Managed Brave policy (`environment.etc."brave/policies/managed/policies.json"`), incl. default search provider (Brave Search) and force-pinned Bitwarden toolbar entry |
| `gui/flatpak.nix` | Bazaar (`pkgs.bazaar`) plus a `flatpak-remotes` oneshot registering the `flathub` and `flathub-beta` system remotes it shows |
| `gui/hyprland.nix` | Noctalia greeter display manager, `programs.hyprland.enable`, `services.flatpak.enable`, Steam, fonts, Grayjay flatpak service, `NAUTILUS_4_EXTENSION_DIR` session variable (nautilus-python, for the Nextcloud client's Nautilus integration) |
| `console/default.nix` | Imports `./session.nix`, `./performance.nix`, `./input.nix`, `./launchers.nix`, `./streaming.nix`, `./desktop.nix`; boot quiet/plymouth settings (no `services.xserver.enable` — gamescope needs no X server stack). Console-only: reaches neither desktop nor laptop |
| `console/session.nix` | `programs.gamescope.capSysNice`, `programs.steam` (incl. `gamescopeSession.enable`, `gamescopeSession.args = [ "--mangoapp" ]`, `gamescopeSession.steamArgs = [ "-tenfoot" "-pipewire-dmabuf" "-steamos3" ]` — `-steamos3` is what makes Steam's "Switch to Desktop" call `steamos-session-select` at all, `protontricks.enable`, `extraPackages = [ steamos-session-select ]`), `services.greetd` autologin into `console-session` (a loop that reads Steam's "Switch to Desktop" request and starts either `steam-gamescope` or the Hyprland/Noctalia session from `./desktop.nix` — launched through the package's `start-hyprland` watchdog with `--path` at the `security.wrappers.Hyprland` wrapper, so the compositor keeps cap_sys_nice without its "started without start-hyprland" warning — falling back to `tuigreet` when neither is requested), `services.pipewire`/`security.rtkit`, bluetooth/flatpak/polkit/dconf |
| `console/performance.nix` | CachyOS-style tuning: `services.scx` (`scx_lavd`), `services.ananicy` (`ananicy-cpp` + `ananicy-rules-cachyos`), `programs.gamemode`, `vm.max_map_count` sysctl, `boot.kernelModules = [ "ntsync" ]` + udev uaccess rule, `services.lact.enable` |
| `console/input.nix` | `hardware.xone.enable`, `hardware.xpadneo.enable` (Xbox controllers, dongle + Bluetooth), `services.udev.packages = [ pkgs.game-devices-udev-rules ]`, `hardware.uinput.enable` |
| `console/launchers.nix` | `environment.systemPackages`: `heroic`, `protonup-qt`, `mangohud`, `lutris`, `umu-launcher`, callpackaged `opengameinstaller`, `bun` (OGI's NixOS branch expects Bun on PATH and offers no installer), `unrar` (OGI addons, Lutris and umu extract RAR archives by shelling out to unrar), `python3` (interpreter for the umu zipapp OGI downloads under `~/.local/share/OpenGameInstaller/bin/umu/` — OGI does not use the nixpkgs `umu-launcher` for its own game flow); `systemd.services.chromium-flatpak` installs/updates `org.chromium.Chromium` from Flathub for OGI's genesis-lib addon, mirroring `gui/hyprland.nix`'s `grayjay-flatpak` |
| `console/streaming.nix` | `services.sunshine` (`enable`, `capSysAdmin`, `openFirewall`, `autoStart`) |
| `console/desktop.nix` | Imports `../gui/brave.nix` (standalone `environment.etc` entry, carries Brave's managed policy without the rest of `gui/`) and `../gui/flatpak.nix` (Bazaar + the `flatpak-remotes` oneshot; `services.flatpak.enable` is already on via `./session.nix`); `programs.hyprland` (`enable`, `xwayland.enable`), `services.gvfs`/`services.udisks2` (for the console profile's nautilus), `environment.pathsToLink`, `fonts.packages` (Noctalia's icon/text fonts, copied from `gui/hyprland.nix`) — a console-only copy, not an import, of `gui/hyprland.nix`'s system layer; deliberately omits `services.displayManager.noctalia-greeter` (would double-define `services.greetd.settings.default_session` against `./session.nix`), Grayjay, kdeconnect, gnome-keyring and `services.xserver.enable` |

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
| Desktop applications | `bitwarden-desktop`, `bolt-launcher`, `ente-auth`, `firefox`, `github-desktop`, `gnome-calendar`, `gnome-disk-utility`, `lmstudio`, `mission-center`, `nautilus`, `obsidian`, `netbird-ui`, `paperweight`, `papers`, `proton-authenticator`, `proton-pass`, `proton-vpn`, `protonmail-bridge-gui`, `protonmail-desktop`, `runelite`, `signal-desktop`, `telegram-desktop`, `discord.override { withVencord = true; }`, `vscodium` |
| Unix tools | `age`, `ansible`, `bitwarden-cli`, `cloudflared`, `crane`, `fluxcd`, `gh`, `go-task`, `helmfile`, `kubeconform`, `kubecolor`, `kubectl`, `kubernetes-helm`, `kustomize`, `minijinja`, `mise`, `ranger`, `fd`, `sd`, `sops`, `stern`, `talhelper`, `talosctl`, `terraform`, `tree`, `gnumake`, `yamllint`, `yq-go`, `proton-pass-cli`, `_1password-cli` |
| Nix dev | `cachix`, `nil`, `nix-info`, `nixpkgs-fmt` |
| Other | `less` (man pager) |

### `programs.*` enabled in `modules/home/packages.nix`

`jq`, `btop`, `tmate` (all `enable = true`). `bat`, `fzf`, `eza` moved to
`modules/home/shell.nix`, along with `ripgrep` (`home.packages`), so the
console's `shell` import gets the tools its aliases need.

`modules/home/fastfetch.nix` additionally adds `home.packages = [ pkgs.fastfetch ]`.

### System packages

`environment.systemPackages = [ pkgs.docker-compose ]` in `modules/nixos/default.nix`
(only system-level package; everything else is installed per-user via home-manager).

## Repo-local packages — `packages/`

| Package | File | Notes |
| --- | --- | --- |
| paperweight | `packages/paperweight.nix` | Callpackaged in `modules/home/packages.nix` |
| mactahoe-gtk-theme | `packages/mactahoe-gtk-theme.nix` | MacTahoe-Dark GTK theme, tinted at build time from the founder palette; consumed by `modules/home/theme/mactahoe.nix` |
| wallpapers | `packages/wallpapers.nix` | Wallpaper collection (SHOA-1058, `packages/wallpapers/assets/`); consumed by `modules/home/noctalia.nix` |
| opengameinstaller | `packages/opengameinstaller.nix` | AppImage-wrapped OpenGameInstaller front-end; callpackaged in `modules/nixos/console/launchers.nix`; wrapper exports `APPIMAGE=/run/current-system/sw/bin/opengameinstaller` so OGI's Steam/desktop shortcut writers point at the FHS launcher |
