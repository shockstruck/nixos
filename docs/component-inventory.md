# Component inventory

Captured against branch head of the `shoa-1024` flake (Lead commit `c455f73` reconciled
`flake.lock`; this doc is not imported by the flake and does not affect the build).

## Flake inputs

Every top-level input of `flake.nix`, with its declared source URL and the locked
rev recorded in `flake.lock` (12-char rev shown). The lockfile records revs only —
no `ref` fields are captured — so the URL refs below are the declared refs from
`flake.nix`.

| Input | Source URL | Locked rev | Follows |
| --- | --- | --- | --- |
| nixpkgs | `github:nixos/nixpkgs/nixos-unstable` | `0e251e24a4f2` | — |
| nix-darwin | `github:LnL7/nix-darwin` | `15abb8c98f33` | nixpkgs |
| home-manager | `github:nix-community/home-manager` | `c8058ecc1329` | nixpkgs |
| disko | `github:nix-community/disko` | `ff8702b4de27` | nixpkgs |
| flake-parts | `github:hercules-ci/flake-parts` | `427bf4bd9435` | — |
| nixos-hardware | `github:NixOS/nixos-hardware` | `2dda192987ab` | nixpkgs |
| nixos-unified | `github:srid/nixos-unified` | `d2818c36b863` | — |
| niri-flake | `github:sodiboo/niri-flake` | `9ee3e13b6064` | nixpkgs |
| stasis | `github:saltnpepper97/stasis/v1.5.1` | `f17d1a09e0e4` | nixpkgs, flake-parts |
| nix-index-database | `github:nix-community/nix-index-database` | `14d55b806911` | nixpkgs |
| nixvim | `github:nix-community/nixvim` | `738351a7813b` | nixpkgs, flake-parts |
| noctalia | `github:noctalia-dev/noctalia-shell/v5.0.0-beta.9` | `a064c063f204` | nixpkgs |

Inputs that follow `nixpkgs`: `nix-darwin`, `home-manager`, `disko`, `nixos-hardware`,
`niri-flake`, `stasis`, `nix-index-database`, `nixvim`, `noctalia`. `stasis` and
`nixvim` additionally follow `flake-parts`. `flake-parts` and `nixos-unified` pin
their own nixpkgs.

The flake is wired via `inputs.nixos-unified.lib.mkFlake` (autowiring), for systems
`x86_64-linux`, `aarch64-linux`, `aarch64-darwin`.

## Hosts

Both hosts are `x86_64-linux` NixOS configurations under `configurations/nixos/`.
Each imports `self.nixosModules.default` + `self.nixosModules.gui` +
`inputs.disko.nixosModules.disko` plus its local boot/hardware/graphics/power/storage
modules:

| Host | Config | Hostname | Host platform | Local imports |
| --- | --- | --- | --- | --- |
| desktop | `configurations/nixos/desktop/default.nix` | `desktop` | `x86_64-linux` | `./boot.nix`, `./hardware.nix`, `./graphics.nix`, `./power.nix`, `./storage.nix` |
| laptop | `configurations/nixos/laptop/default.nix` | `laptop` | `x86_64-linux` | `./boot.nix`, `./hardware.nix`, `./graphics.nix`, `./power.nix`, `./storage.nix` |

## Imported modules

### Home modules — `modules/home/`

`modules/home/default.nix` auto-imports every sibling entry whose name is not
`default.nix` via `attrNames (readDir ./.)`; directory entries (`neovim`, `theme`)
resolve to their `default.nix`.

| Module | Purpose |
| --- | --- |
| `bitwarden.nix` | Bitwarden vault config |
| `direnv.nix` | direnv setup |
| `gc.nix` | Home-manager garbage collection |
| `git.nix` | Git config |
| `idle.nix` | Idle management via `services.stasis` (stasis v1.5.1); drives the noctalialock lock (SHOA-1026) |
| `kitty.nix` | Kitty terminal config |
| `me.nix` | User config |
| `neovim/default.nix` | Imports nixvim home module; `programs.nixvim = import ./nixvim.nix` |
| `niri.nix` | niri compositor home config; binds `niri-ror` run-or-raise helper |
| `nix-index.nix` | nix-index database setup |
| `nix.nix` | Nix client settings |
| `noctalia.nix` | Noctalia V5 shell (`programs.noctalia`, systemd user service) |
| `packages.nix` | `home.packages` list + `programs.*` (see below) |
| `shell.nix` | Shell config (zsh, p10k, eza aliases) |
| ~~locker module~~ (removed, SHOA-1026) | Locking moved to Noctalia's built-in lock screen (noctalialock): `idle.nix` + niri Mod+L run `noctalia msg session lock`; PAM via the standard `login` service |
| `theme/default.nix` | Aggregates theme modules → `./eldritch.nix` |
| `work.nix` | Work-specific config |

### NixOS modules — `modules/nixos/`

| Module | Contents |
| --- | --- |
| `default.nix` | Imports `common`; firmware, `environment.systemPackages = [ pkgs.docker-compose ]`, networkmanager, `nixpkgs.config.allowUnfree`, netbird, openssh, timezone `America/Detroit`, docker, zramSwap |
| `common/default.nix` | Imports `./myusers.nix` |
| `common/myusers.nix` | Declares the `myusers` option and per-user top-level configuration |
| `gui/default.nix` | Imports `./niri.nix`; boot console/quiet/plymouth settings, `services.xserver.enable` |
| `gui/niri.nix` | Imports niri-flake's NixOS module; `programs.niri.enable`, xdg portals/polkit wiring |

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
| Desktop applications | `bitwarden-desktop`, `bolt-launcher`, `brave`, `firefox`, `github-desktop`, `gnome-calendar`, `gnome-disk-utility`, `mission-center`, `obsidian`, `netbird-ui`, `paperweight`, `proton-authenticator`, `proton-pass`, `proton-vpn`, `protonmail-bridge-gui`, `protonmail-desktop`, `runelite`, `signal-desktop`, `splayer-next`, `telegram-desktop`, `discord.override { withVencord = true; }`, `vicinae`, `vscodium` |
| Unix tools | `age`, `ansible`, `bitwarden-cli`, `cloudflared`, `crane`, `fluxcd`, `gh`, `go-task`, `helmfile`, `kubeconform`, `kubecolor`, `kubectl`, `kubernetes-helm`, `kustomize`, `minijinja`, `mise`, `niri-ror`, `ranger`, `ripgrep`, `fd`, `sd`, `sops`, `stern`, `talhelper`, `talosctl`, `terraform`, `tree`, `gnumake`, `yamllint`, `yq-go`, `proton-pass-cli`, `_1password-cli` |
| Nix dev | `cachix`, `nil`, `nix-info`, `nixpkgs-fmt` |
| Other | `less` (man pager) |

### `programs.*` enabled in `modules/home/packages.nix`

`bat`, `fzf`, `jq`, `btop`, `eza`, `tmate` (all `enable = true`).

### System packages

`environment.systemPackages = [ pkgs.docker-compose ]` in `modules/nixos/default.nix`
(only system-level package; everything else is installed per-user via home-manager).

## Repo-local packages — `packages/`

| Package | File | Notes |
| --- | --- | --- |
| paperweight | `packages/paperweight.nix` | Callpackaged in `modules/home/packages.nix` |
| splayer-next | `packages/splayer-next.nix` | Callpackaged in `modules/home/packages.nix` |
| niri-ror | `packages/niri-ror.nix` | Run-or-raise helper for niri (SHOA-1001); sources under `packages/niri-ror/src/`; added to `home.packages` and bound in `modules/home/niri.nix` |
