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

## Pre-install checks

The Disko layouts assume the target disk is `/dev/nvme0n1`. Confirm the disk
name, size, and model from the NixOS installer before running any destructive
command:

```sh
lsblk -d -o NAME,SIZE,MODEL,TRAN
```

The laptop PRIME configuration expects the Intel GPU at `0000:00:02.0` and the
NVIDIA GPU at `0000:01:00.0`. Confirm both addresses before installation:

```sh
lspci -D -nn | grep -E 'VGA|3D'
```

NixOS expresses those addresses as `PCI:0:2:0` and `PCI:1:0:0`. Update
`configurations/nixos/laptop/graphics.nix` if the hardware reports different
addresses.

## Install

The following Disko command destroys the partition table and all data on the
configured target disk. Run it only from the NixOS installer after validating
the host name, `/dev/nvme0n1`, backups, and laptop GPU addresses.

```sh
# Replace HOST with desktop or laptop.
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

Do not select one machine's host configuration on the other machine.
