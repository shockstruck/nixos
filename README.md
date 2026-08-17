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

Use this sequence from the minimal NixOS installer for the confirmed ThinkPad
P15s Gen 2. This is an intentional clean install. Disko permanently destroys
the existing partition table and data; the wipe cannot be undone.

First clone the repository, or fast-forward an existing clean checkout:

```sh
# New checkout:
git clone https://github.com/shockstruck/nixos.git
cd nixos

# Existing checkout instead:
git fetch origin main
git pull --ff-only origin main
```

Before running Disko, perform every preflight check below. The checks stop the
sequence before Disko when the confirmed disk or GPU addresses do not match:

```sh
set -eu

test -b /dev/nvme0n1 || {
  echo "STOP: /dev/nvme0n1 is not present" >&2
  exit 1
}
lsblk -d -o NAME,SIZE,MODEL,TRAN /dev/nvme0n1
target_size_bytes="$(lsblk -dnbo SIZE /dev/nvme0n1)"
test "$target_size_bytes" = "512110190592" || {
  echo "STOP: /dev/nvme0n1 is not the confirmed 476.9 GiB target" >&2
  exit 1
}
read -r -p "Type the confirmed target disk (/dev/nvme0n1): " disk_confirm
test "$disk_confirm" = "/dev/nvme0n1" || {
  echo "STOP: target disk was not confirmed" >&2
  exit 1
}

lspci -D -nn | grep -E 'VGA|3D'
lspci -D -nn | grep -q '^0000:00:02.0 ' || {
  echo "STOP: expected Intel GPU at 0000:00:02.0 was not found" >&2
  exit 1
}
lspci -D -nn | grep -q '^0000:01:00.0 ' || {
  echo "STOP: expected NVIDIA GPU at 0000:01:00.0 was not found" >&2
  exit 1
}
```

The laptop PRIME configuration uses those addresses as `PCI:0:2:0` and
`PCI:1:0:0`. If either address differs, stop and do not run Disko.

Only after the preflight succeeds, read and explicitly confirm this warning:

```text
WARNING: the next command permanently destroys the partition table and all
data on /dev/nvme0n1. This clean-install wipe is intentional and cannot be
undone. Do not continue unless the disk checks, GPU checks, and backups are
correct.
```

```sh
read -r -p "Type DESTROY /dev/nvme0n1 to continue: " wipe_confirm
test "$wipe_confirm" = "DESTROY /dev/nvme0n1" || {
  echo "Aborted before Disko" >&2
  exit 1
}

sudo nix --extra-experimental-features "nix-command flakes" \
  run github:nix-community/disko -- \
  --mode disko --flake .#laptop

sudo nixos-install --flake .#laptop
```

Before rebooting, set Kevin's password interactively inside the installed
system mounted at `/mnt`. The source intentionally contains no initial
password or password hash:

```sh
sudo nixos-enter --root /mnt -c 'passwd kevin'
sudo reboot
```

## Install another host

For a normal installation of a different host, validate that host's target
disk and backups before running the same generic Disko flow. Use `.#desktop`
for the desktop and `.#laptop` for the laptop; do not select one machine's
configuration on the other machine.

```sh
# Replace HOST with desktop or laptop after validating the matching hardware.
sudo nix --extra-experimental-features "nix-command flakes" \
  run github:nix-community/disko -- \
  --mode disko --flake .#HOST

sudo nixos-install --flake .#HOST
```

After rebooting into an installed system, select the matching host explicitly
for future source-controlled updates:

```sh
# Replace HOST with desktop or laptop.
sudo nixos-rebuild switch --flake .#HOST
```
