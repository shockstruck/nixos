# Component inventory

Captured against `origin/main` @ `75a9f74` (2026-08-25). This doc is not
imported by the flake and does not affect the build; it is a living inventory
that must be re-verified against `main` whenever the flake changes.

## Flake inputs

Every top-level input of `flake.nix`, with its declared source URL and the locked
rev recorded in `flake.lock` (12-char rev shown). The lockfile records revs only —
no `ref` fields are captured — so the URL refs below are the declared refs from
`flake.nix`.

| Input | Source URL | Locked rev | Follows |
| --- | --- | --- | --- |
| nixpkgs | `github:nixos/nixpkgs/nixos-unstable` | `2c423e03bbaf` | — |
| nix-darwin | `github:LnL7/nix-darwin` | `4cff07de74b5` | nixpkgs |
| home-manager | `github:nix-community/home-manager` | `ec1a8fdf74ed` | nixpkgs |
| disko | `github:nix-community/disko` | `ff8702b4de27` | nixpkgs |
| flake-parts | `github:hercules-ci/flake-parts` | `427bf4bd9435` | — |
| nixos-hardware | `github:NixOS/nixos-hardware` | `0471accf8d0a` | nixpkgs |
| nixos-unified | `github:srid/nixos-unified` | `d2818c36b863` | — |
| stasis | `github:saltnpepper97/stasis/v1.5.1` | `f17d1a09e0e4` | nixpkgs, flake-parts |
| nix-index-database | `github:nix-community/nix-index-database` | `c7962dc97b45` | nixpkgs |
| nixvim | `github:nix-community/nixvim` | `bd46166bd830` | nixpkgs, flake-parts |
| noctalia | `github:noctalia-dev/noctalia-shell/v5.0.0-beta.9` | `a064c063f204` | nixpkgs |

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

Both hosts are `x86_64-linux` NixOS configurations under `configurations/nixos/`.
Each imports `self.nixosModules.default` + `self.nixosModules.gui` +
`inputs.disko.nixosModules.disko` plus its local boot/hardware/graphics/power/storage
modules:

| Host | Config | Hostname | Host platform | State version | Local imports |
| --- | --- | --- | --- | --- | --- |
| desktop | `configurations/nixos/desktop/default.nix` | `desktop` | `x86_64-linux` | `24.11` | `./boot.nix`, `./hardware.nix`, `./graphics.nix`, `./power.nix`, `./storage.nix` |
| laptop | `configurations/nixos/laptop/default.nix` | `laptop` | `x86_64-linux` | `24.11` | `./boot.nix`, `./hardware.nix`, `./graphics.nix`, `./power.nix`, `./storage.nix` |

`configurations/home/kevin.nix` defines the shared home configuration (`me =
{ username = "kevin"; … }`, imports `self.homeModules.default`,
`home.stateVersion = "26.05"`). `configurations/darwin/example.nix` is the
un-wired nix-darwin example configuration.

## Imported modules

### Home modules — `modules/home/`

`modules/home/default.nix` auto-imports every sibling entry whose name is not
`default.nix` via `attrNames (readDir ./)`; directory entries (`neovim`, `theme`)
resolve to their `default.nix`.

| Module | Purpose |
| --- | --- |
| `bitwarden.nix` | Bitwarden vault config + `bw-ssh-pull` helper script |
| `direnv.nix` | direnv setup (`programs.direnv` with `nix-direnv`) |
| `fastfetch.nix` | fastfetch with the Noctalia theme + NGR logo (SHOA-1058) |
| `gc.nix` | Home-manager garbage collection |
| `git.nix` | Git config (`programs.git`, `lazygit`) + aliases (`g`, `lg`) |
| `hyprland.nix` | Hyprland compositor home config (SHOA-1037); `wayland.windowManager.hyprland`, pointer cursor, keybinds incl. `noctalia msg session lock` |
| `idle.nix` | Idle management via `services.stasis` (stasis v1.5.1, SHOA-1040); stasis RUNE plan drives Noctalia's native lock screen |
| `kitty.nix` | Kitty terminal config (founder palette) |
| `me.nix` | User config options (`me.username`, `me.fullname`, `me.email`) |
| `neovim/default.nix` | Imports nixvim home module; `programs.nixvim = import ./nixvim.nix` |
| `neovim/nixvim.nix` | nixvim configuration for neovim |
| `nix-index.nix` | nix-index database setup |
| `nix.nix` | Nix client settings |
| `noctalia.nix` | Noctalia V5 shell (`programs.noctalia`, systemd user service, founder palette) |
| `packages.nix` | `home.packages` list + `programs.*` (see below) |
| `shell.nix` | Shell config (zsh, p10k, eza aliases) |
| `ssh.nix` | `programs.ssh` github.com host config (SHOA-1092) |
| `theme/default.nix` | Aggregates theme modules → `./eldritch.nix`, `./founder.nix`, `./mactahoe.nix` |
| `theme/eldritch.nix` | Eldritch base16 palette (SHOA-999); still exported as a Noctalia custom palette, no longer the default |
| `theme/founder.nix` | Founder palette (SHOA-1094); single source of truth for theme colors |
| `theme/mactahoe.nix` | MacTahoe-Dark GTK theme tinted from the founder palette (SHOA-1094) |
| `work.nix` | Work-specific config (zsh/bash `initExtra`, e.g. macOS linker `ulimit`) |

### NixOS modules — `modules/nixos/`

| Module | Contents |
| --- | --- |
| `default.nix` | Imports `common`; firmware, `environment.systemPackages = [ pkgs.docker-compose ]`, networkmanager, `nixpkgs.config.allowUnfree`, netbird, openssh, timezone `America/Detroit`, docker, zramSwap |
| `common/default.nix` | Imports `./myusers.nix` |
| `common/myusers.nix` | Declares the `myusers` option and per-user top-level configuration; system-wide `programs.zsh.enable` |
| `gui/default.nix` | Imports `./hyprland.nix`; boot console/quiet/plymouth settings, `services.xserver.enable` |
| `gui/hyprland.nix` | Noctalia greeter display manager, `programs.hyprland.enable`, Steam, fonts, flatpak/Grayjay service |

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
| Desktop applications | `bitwarden-desktop`, `bolt-launcher`, `brave`, `ente-auth`, `firefox`, `github-desktop`, `gnome-calendar`, `gnome-disk-utility`, `lmstudio`, `mission-center`, `nautilus`, `obsidian`, `netbird-ui`, `paperweight`, `papers`, `proton-authenticator`, `proton-pass`, `proton-vpn`, `protonmail-bridge-gui`, `protonmail-desktop`, `runelite`, `signal-desktop`, `splayer-next`, `telegram-desktop`, `discord.override { withVencord = true; }`, `vicinae`, `vscodium` |
| Unix tools | `age`, `ansible`, `bitwarden-cli`, `cloudflared`, `crane`, `fluxcd`, `gh`, `go-task`, `helmfile`, `kubeconform`, `kubecolor`, `kubectl`, `kubernetes-helm`, `kustomize`, `minijinja`, `mise`, `ranger`, `ripgrep`, `fd`, `sd`, `sops`, `stern`, `talhelper`, `talosctl`, `terraform`, `tree`, `gnumake`, `yamllint`, `yq-go`, `proton-pass-cli`, `_1password-cli` |
| Nix dev | `cachix`, `nil`, `nix-info`, `nixpkgs-fmt` |
| Other | `less` (man pager) |

### `programs.*` enabled in `modules/home/packages.nix`

`bat`, `fzf`, `jq`, `btop`, `eza`, `tmate` (all `enable = true`).

`modules/home/fastfetch.nix` additionally adds `home.packages = [ pkgs.fastfetch ]`.

### System packages

`environment.systemPackages = [ pkgs.docker-compose ]` in `modules/nixos/default.nix`
(only system-level package; everything else is installed per-user via home-manager).

## Repo-local packages — `packages/`

| Package | File | Notes |
| --- | --- | --- |
| paperweight | `packages/paperweight.nix` | Callpackaged in `modules/home/packages.nix` |
| splayer-next | `packages/splayer-next.nix` | Callpackaged in `modules/home/packages.nix` |
| mactahoe-gtk-theme | `packages/mactahoe-gtk-theme.nix` | MacTahoe-Dark GTK theme, tinted at build time from the founder palette; consumed by `modules/home/theme/mactahoe.nix` |
| wallpapers | `packages/wallpapers.nix` | Wallpaper collection (SHOA-1058, `packages/wallpapers/assets/`); consumed by `modules/home/noctalia.nix` |
