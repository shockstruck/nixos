# NixOS workstations

This flake defines two NixOS workstations with one shared user and system
configuration. Hardware-dependent settings stay in each host directory.

| Host | Hardware | Storage |
| --- | --- | --- |
| `desktop` | AMD Ryzen 9 7950X and Radeon RX 7900 XT | 1 TB NVMe |
| `laptop` | Lenovo ThinkPad P15s Gen 2, 11th-generation Intel CPU, Intel iGPU, and 4 GB NVIDIA T500 dGPU | 512 GB NVMe |

Both hosts import the shared modules under `modules/nixos` and the same
home-manager configuration under `configurations/home`. The host trees under
`configurations/nixos` contain only boot, hardware, graphics, power, and disk
layout differences.

## Desktop session

Both workstations share one declarative Wayland session:

- **Hyprland** (`modules/nixos/gui/hyprland.nix`) is the compositor, enabled with
  XWayland. GDM stays as the display manager and selects the `hyprland` session
  by default. The previous GNOME desktop is removed.
- **DankMaterialShell** is integrated through its first-party Home Manager
  module. DMS provides the bar, launcher, settings, clipboard, wallpaper,
  notifications, power menu, media controls, and Sathi.AI chat, while this
  repository remains the source of truth for Hyprland and Fish. Its
  `dms.service` starts with `hyprland-session.target`.
- **Home Manager** Hyprland config lives in `modules/home/hyprland.nix`, which is
  auto-imported by `modules/home` and therefore shared by every host. It provides
  the Lua main config, systemd graphical-session integration, the shared
  keybindings below, and the declarative Hyprland plugin load described under
  [Hyprland plugins](#hyprland-plugins).
- **DMS display settings** remain writable under `~/.config/hypr/dms`. The
  initial output uses preferred mode, automatic placement, and scale `1`; DMS
  owns its display, layout, color, cursor, shortcut, and window-rule Lua
  fragments while GDM remains the login greeter. The laptop bar includes the
  battery widget.
- **Session locking** uses the native DMS lock screen.
- **File management** uses Nautilus with GVfs/UDisks integration. KDE Connect is
  retained, but Dolphin and KDE System Settings are not installed.
- **Input defaults** enable Num Lock in GDM and Hyprland on both hosts. The
  laptop also sets its ThinkPad keyboard backlight to full brightness at boot.
- **Theme**: the first DMS session starts with its dark stock green theme and
  dynamic theming enabled. Runtime settings remain writable under
  `~/.config/DankMaterialShell`; activation only enforces the launcher OS logos,
  dock launcher and trash, workspace app grouping, clock seconds, and weather
  units/location. Both hosts use the `America/Detroit` timezone.
- **Boot splash**: the NixOS-branded Breeze Plymouth animation replaces routine
  boot messages while preserving automatic status output for failures.

> DMS and the Sathi.AI plugin are pinned as `dank-material-shell` and `sathi-ai`
> in `flake.lock`; rebuild both hosts after updating either input.

### Keybindings

`SUPER` is the main modifier.

| Binding | Action |
| --- | --- |
| `SUPER`+`Return` | Launch `foot` |
| `SUPER`+`Q` | Close the focused window |
| `SUPER`+`←` `→` `↑` `↓` | Move focus |
| `SUPER`+`1`…`5` | Switch to workspace 1-5 |
| `SUPER`+`SHIFT`+`1`…`5` | Move window to workspace 1-5 |
| `SUPER`+`Space` | Toggle the DMS application launcher |
| `SUPER`+`S` | Toggle DMS settings |
| `SUPER`+`C` | Toggle the clipboard history |
| `SUPER`+`W` | Open the wallpaper chooser |
| `SUPER`+`SHIFT`+`E` | Toggle the power menu |
| `SUPER`+`A` | Toggle Sathi.AI chat |
| `SUPER`+`N` | Toggle the control center |
| `SUPER`+`M` | Toggle the media dashboard |
| `SUPER`+`P` | Toggle the process list |
| `SUPER`+`D` | Open DMS settings for display configuration |
| `SUPER`+`Tab` | Toggle the workspace overview |
| `SUPER`+`/` | Toggle the DMS keybinding cheatsheet |
| `SUPER`+`CTRL`+`A` | Toggle hypr-autoscroll middle-button autoscroll |

`foot` is installed declaratively by the shared GUI module so the terminal
binding works on every host.

## Local AI

The laptop runs Ollama as a localhost-only NixOS service using the CUDA build.
It starts at boot after the T500 driver and preloaded NVIDIA UVM module are
ready, selects its CUDA runner, and enables Flash Attention with an 8-bit KV
cache. The laptop CLI uses the same CUDA package. Its model loader downloads
`nemotron-3-nano:4b` after networking becomes available. This is the 2.8 GB
Q4_K_M release; Ollama is capped to a 4,096-token context so its weights and
runtime cache fit the T500's 4 GB VRAM budget.

The desktop runs the same boot-time service through Ollama's ROCm package,
which natively supports its Radeon RX 7900 XT, and preloads `qwen3.5:9b`.
Both services remain localhost-only.

The first boot can finish before the background model download completes. Check
its progress or run the model with:

```sh
systemctl status ollama-model-loader.service
journalctl -u ollama-model-loader.service -f
ollama run nemotron-3-nano:4b
ollama run qwen3.5:9b
ollama ps
```

## Hyprland plugins

`hypr-autoscroll` is a Hyprland compositor plugin (Windows-style middle-click
autoscroll) packaged from source in `packages/hypr-autoscroll.nix` and loaded
declaratively for every host through Home Manager. It is **not** installed with
`hyprpm`, the upstream setup script, or any mutable per-user plugin cache; the
build artifact is the single `lib/libhypr-autoscroll.so` Home Manager loads from
the Nix store.

- **Purpose**: enables middle-button autoscroll; `direct_activation = false` keeps
  the mode off by default so it only starts when toggled.
- **SUPER+CTRL+A**: toggles middle-button autoscroll mode on and off
  (`hypr-autoscroll:middle-mode, toggle`) without replacing the AI sidebar
  binding.
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

If a DMS input was just added or changed, refresh its lock graph first
(non-activating):

```sh
nix flake lock --update-input dank-material-shell
nix flake lock --update-input sathi-ai
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
available, exactly one usable TPM2 device is visible, the laptop target is the
confirmed 476.9 GiB size, and the laptop GPU identities match the configured
addresses:

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
cannot be undone. It leaves the 1 GiB EFI system partition unencrypted and
creates the Btrfs root, home, and Nix subvolumes inside a LUKS2 volume. During
formatting, enter a LUKS passphrase twice. The installer then enrolls the same
volume for TPM2 automatic unlock and asks for that passphrase once more before
running `nixos-install`.

The TPM enrollment intentionally has no PCR binding because Secure Boot is not
configured. This keeps NixOS generation changes bootable without re-enrollment;
it protects a removed disk or a disk whose TPM has been cleared, but not against
an attacker who controls the complete machine and its unverified boot chain. If
TPM unlock is unavailable, boot falls back to the LUKS passphrase.

The installer runs Disko with `--mode destroy,format,mount` and the exact
`--flake ".#laptop"` selector, followed by:

```sh
sudo nixos-install --flake ".#laptop"
sudo nixos-enter --root "/mnt" -c "passwd kevin"
```

The source has no initial password, password hash, or disk key. The LUKS and
account passwords are entered only at interactive prompts, and the installer
never prints or declares them. It never reboots automatically. After the
installer reports success, reboot manually:

```sh
sudo reboot
```

## Install another host

For a normal installation of the desktop, validate the target disk, TPM2, and
backups and use the same guarded encrypted installer with the matching explicit
host selector. Do not select one machine's configuration on the other machine.

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
