# NixOS workstations

This flake defines two NixOS workstations with one shared user and system
configuration. Hardware-dependent settings stay in each host directory.

| Host | Hardware | Storage |
| --- | --- | --- |
| `desktop` | AMD Ryzen 9 7950X and Radeon RX 7900 XT | 1 TB NVMe |
| `laptop` | Lenovo ThinkPad P15s Gen 2, 11th-generation Intel CPU, Intel iGPU, and NVIDIA dGPU | 512 GB NVMe |

Both hosts import the shared modules under `modules/nixos` and the same
home-manager configuration under `configurations/home`. The host trees under
`configurations/nixos` contain only boot, hardware, graphics, power, and disk
layout differences.

## Desktop session

Both workstations share one declarative Wayland session:

- **Hyprland** (`modules/nixos/gui/hyprland.nix`) is the compositor, enabled with
  XWayland. GDM stays as the only display manager and selects the `hyprland`
  session by default. The previous GNOME desktop is removed.
- **Vast Shell** is integrated through its upstream NixOS flake module
  (`vast-shell.nixosModules.default`) and enabled with `programs.quickshell-shell`.
  Vast Shell's own `quickshell-shell.service` (bound to
  `graphical-session.target`) owns shell startup; no second autostart is added.
- **Home Manager** Hyprland config lives in `modules/home/hyprland.nix`, which is
  auto-imported by `modules/home` and therefore shared by every host. It provides
  a monitor fallback (`preferred` mode, automatic placement, scale `1`), systemd
  graphical-session integration, the shared keybindings below, and the
  declarative Hyprland plugin load described under
  [Hyprland plugins](#hyprland-plugins).

> Vast Shell is under active upstream development. Features may change without
> notice; pin a specific `vast-shell` revision in `flake.lock` before relying on
> a particular panel.

### Keybindings

`SUPER` is the main modifier.

| Binding | Action |
| --- | --- |
| `SUPER`+`Return` | Launch `foot` |
| `SUPER`+`Q` | Close the focused window |
| `SUPER`+`←` `→` `↑` `↓` | Move focus |
| `SUPER`+`1`…`5` | Switch to workspace 1-5 |
| `SUPER`+`SHIFT`+`1`…`5` | Move window to workspace 1-5 |
| `SUPER`+`Space` | Vast Shell app launcher |
| `SUPER`+`S` | Vast Shell quick settings |
| `SUPER`+`C` | Vast Shell clipboard |
| `SUPER`+`W` | Vast Shell wallpaper switcher |
| `SUPER`+`SHIFT`+`E` | Vast Shell session menu |
| `SUPER`+`A` | Toggle hypr-autoscroll middle-button autoscroll |

`foot` is installed declaratively by the shared GUI module so the terminal
binding works on every host.

## Hyprland plugins

`hypr-autoscroll` is a Hyprland compositor plugin (Windows-style middle-click
autoscroll) packaged from source in `packages/hypr-autoscroll.nix` and loaded
declaratively for every host through Home Manager. It is **not** installed with
`hyprpm`, the upstream setup script, or any mutable per-user plugin cache; the
build artifact is the single `lib/libhypr-autoscroll.so` Home Manager loads from
the Nix store.

- **Purpose**: enables middle-button autoscroll; `direct_activation = false` keeps
  the mode off by default so it only starts when toggled.
- **SUPER+A**: the non-conflicting binding that toggles middle-button autoscroll
  mode on and off (`hypr-autoscroll:middle-mode, toggle`).
- **ABI sensitivity**: the plugin compiles against the exact configured Hyprland
  package (`config.wayland.windowManager.hyprland.finalPackage`). Hyprland's
  plugin ABI is unstable, so every Hyprland or input change must rebuild and
  re-validate the plugin; a version skew fails the build rather than loading a
  mismatched `.so`.
- **Pinned rebuild**: the source is pinned through the non-flake `hypr-autoscroll`
  input (`github:estebanhiram/hypr-autoscroll`) whose exact revision and NAR hash
  live in `flake.lock`. After editing the input, refresh only its lock graph
  (non-activating):

  ```sh
  nix flake lock --update-input hypr-autoscroll
  ```

- **Validation**: evaluate and build both hosts without activating anything:

  ```sh
  nix eval .#nixosConfigurations.desktop.config.system.build.toplevel.drvPath
  nix eval .#nixosConfigurations.laptop.config.system.build.toplevel.drvPath
  nix build --no-link .#nixosConfigurations.desktop.config.system.build.toplevel
  nix build --no-link .#nixosConfigurations.laptop.config.system.build.toplevel
  nix flake check
  ```

- **Rollout**: source-only. Land the accepted diff once, then rebuild one host at
  a time (`sudo nixos-rebuild switch --flake .#HOST`).
- **Rollback**: revert the integration commit and rebuild the affected host. A
  failed plugin load must not be worked around with mutable `hyprpm` state.

  ```sh
  git revert <integration-commit>
  sudo nixos-rebuild switch --flake .#HOST
  ```

## Validate

Evaluate both configurations without changing a running system:

```sh
nix eval .#nixosConfigurations.desktop.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.laptop.config.system.build.toplevel.drvPath
```

Build both system closures without creating a result symlink:

```sh
nix build --no-link .#nixosConfigurations.desktop.config.system.build.toplevel
nix build --no-link .#nixosConfigurations.laptop.config.system.build.toplevel
nix flake check
```

If the `vast-shell` input was just added or changed, refresh its lock graph first
(non-activating):

```sh
nix flake lock --update-input vast-shell
```

## Apply changes

Roll out an accepted change to one host at a time, selecting that host's
configuration explicitly:

```sh
# Replace HOST with desktop or laptop.
sudo nixos-rebuild switch --flake .#HOST
```

Roll back an accepted change that has already landed with a Git revert followed
by the host rebuild:

```sh
git revert <integration-commit>
sudo nixos-rebuild switch --flake .#HOST
```

### TTY recovery

If the Hyprland session fails to start after a rebuild, switch to a virtual
console (`Ctrl`+`Alt`+`F3`), sign in, and roll the host back to its previous
generation without using the display manager:

```sh
sudo nixos-rebuild switch --rollback --flake .#HOST
```

## Fresh laptop install

Use the checked-in installer from the minimal NixOS installer for the confirmed
ThinkPad P15s Gen 2. Boot the ISO in UEFI mode, then clone the repository or
fast-forward an existing clean checkout:

```sh
# New checkout:
git clone https://github.com/shockstruck/nixos.git
cd nixos

# Existing checkout instead:
git fetch origin main
git pull --ff-only origin main
```

Run the installer with both selections explicit. Omitting either option prompts
for it; hardware detection is read-only and advisory and never selects a host
or disk. The installer displays the CPU, GPU, target disk model/size,
partitions, and mounts, then stops unless the target is a whole disk, UEFI is
available, the laptop target is the confirmed 476.9 GiB size, and the laptop
GPU identities match the configured addresses:

```sh
./install.sh --host laptop --disk /dev/nvme0n1
```

The laptop PRIME configuration uses Intel `0000:00:02.0` and NVIDIA
`0000:01:00.0`, with vendor identities `8086` and `10de`. If either address or
vendor identity differs, the installer stops before Disko. It also resolves the
Disko revision from the checked-in `flake.lock` and uses that pinned revision.

The installer requires this exact confirmation. A generic `yes`, `y`, or
different wording fails closed:

```text
Type exactly 'WIPE /dev/nvme0n1 AS laptop' to continue:
```

Disko permanently destroys the existing partition table and data; the wipe
cannot be undone. The installer runs Disko with `--mode destroy,format,mount`
and the exact `--flake ".#laptop"` selector, followed by:

```sh
sudo nixos-install --flake ".#laptop"
sudo nixos-enter --root "/mnt" -c "passwd kevin"
```

Enter the password only at the interactive `passwd` prompt. The source has no
initial password or password hash, the installer never prints or declares a
password, and it never reboots automatically. After the installer reports
success, reboot manually:

```sh
sudo reboot
```

## Install another host

For a normal installation of the desktop, validate the target disk and backups
and use the same guarded installer with the matching explicit host selector.
Do not select one machine's configuration on the other machine.

```sh
# The installer also accepts --host desktop; use the checked-in target disk.
./install.sh --host desktop --disk /dev/nvme0n1
```

After rebooting into an installed system, select the matching host explicitly
for future source-controlled updates:

```sh
# Replace HOST with desktop or laptop.
sudo nixos-rebuild switch --flake .#HOST
```
