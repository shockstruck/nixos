#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./install.sh [--host laptop|desktop] [--disk /dev/...]

Run the guarded clean-install flow from the repository root. If --host or
--disk is omitted, the installer prompts for it explicitly.

The installer never chooses a host or disk from hardware detection. It shows
read-only hardware and mount information, requires one usable TPM2 device and
an exact destructive confirmation, encrypts the root filesystem with LUKS2,
and never reboots automatically.
EOF
}

stop() {
  printf 'STOP: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || stop "required command '$1' is unavailable"
}

host=""
disk=""

while (($# > 0)); do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --host)
      (($# >= 2)) || stop "--host requires laptop or desktop"
      host="$2"
      shift 2
      ;;
    --disk)
      (($# >= 2)) || stop "--disk requires a /dev/... path"
      disk="$2"
      shift 2
      ;;
    *)
      stop "unknown argument: $1"
      ;;
  esac
done

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd -- "$repo_root"

[[ -f "$repo_root/flake.lock" ]] || stop "flake.lock is missing from the repository root"

if [[ -z "$host" ]]; then
  read -r -p "Host to install (laptop|desktop): " host || stop "host prompt was not answered"
fi
if [[ -z "$disk" ]]; then
  read -r -p "Target whole-disk path (/dev/...): " disk || stop "disk prompt was not answered"
fi

case "$host" in
  laptop|desktop)
    ;;
  *)
    stop "invalid host '$host'; expected laptop or desktop"
    ;;
esac

[[ "$disk" == /dev/* ]] || stop "invalid disk '$disk'; expected a /dev/... path"
[[ -b "$disk" ]] || stop "target '$disk' is not an existing block device"

require_command lsblk
require_command findmnt
require_command lspci
disk_type=""
if ! disk_type="$(lsblk -dnro TYPE -- "$disk" 2>/dev/null)"; then
  stop "could not inspect target '$disk'"
fi
disk_type="${disk_type//$'\n'/}"
disk_type="${disk_type//[[:space:]]/}"
[[ "$disk_type" == "disk" ]] || stop "target '$disk' is not a whole disk (reported type: ${disk_type:-unknown})"

if [[ "$host" == laptop ]]; then
  target_size_bytes=""
  if ! target_size_bytes="$(lsblk -dnbo SIZE -- "$disk" 2>/dev/null)"; then
    stop "could not inspect the laptop target size"
  fi
  target_size_bytes="${target_size_bytes//$'\n'/}"
  [[ "$target_size_bytes" == "512110190592" ]] || stop "target '$disk' is not the confirmed 476.9 GiB laptop disk"
fi

printf '%s\n' "Explicit host selection: $host"
printf '%s\n' "Explicit disk selection: $disk"
printf '%s\n' "Hardware detection is advisory only; it never selects or authorizes a host or disk."

printf '\nCPU (advisory):\n'
if command -v lscpu >/dev/null 2>&1; then
  lscpu | grep -E '^(Architecture|CPU\(s\)|Model name):' || true
else
  awk -F: '/^model name/ { sub(/^[[:space:]]+/, "", $2); print "Model name: " $2; exit }' /proc/cpuinfo || true
fi

pci_inventory=""
pci_inventory="$(lspci -D -nn 2>/dev/null || true)"
printf '\nGPU (advisory):\n'
gpu_inventory="$(printf '%s\n' "$pci_inventory" | grep -Ei 'VGA|3D|Display' || true)"
if [[ -n "$gpu_inventory" ]]; then
  printf '%s\n' "$gpu_inventory"
else
  printf '%s\n' 'unavailable or no display controller was reported'
fi

printf '\nTarget disk, partitions, and mounts (read-only inventory):\n'
lsblk -dn -o PATH,SIZE,MODEL,TYPE -- "$disk"
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS -- "$disk"
printf '\nCurrent mounts:\n'
if ! findmnt -rn -o SOURCE,TARGET,FSTYPE,OPTIONS; then
  printf '%s\n' 'no mounts were reported'
fi

if [[ "$host" == laptop ]]; then
  if ! grep -Eiq '^0000:00:02\.0[[:space:]].*(VGA compatible controller|3D controller|Display controller).*\[8086:[[:xdigit:]]{4}\]' <<<"$pci_inventory"; then
    stop "expected Intel GPU vendor 8086 at 0000:00:02.0 was not found"
  fi
  if ! grep -Eiq '^0000:01:00\.0[[:space:]].*(VGA compatible controller|3D controller|Display controller).*\[10de:[[:xdigit:]]{4}\]' <<<"$pci_inventory"; then
    stop "expected NVIDIA GPU vendor 10de at 0000:01:00.0 was not found"
  fi
fi

[[ -d /sys/firmware/efi ]] || stop 'installer was not booted in UEFI mode'

# Both checked-in host Disko definitions use this mkDefault device. Refusing
# another path prevents validating one disk while Disko destroys another.
readonly configured_disk="/dev/nvme0n1"
[[ "$disk" == "$configured_disk" ]] || stop "target '$disk' does not match the checked-in Disko device '$configured_disk'"

require_command nix
require_command sudo
require_command nixos-install
require_command nixos-enter
require_command systemd-cryptenroll

tpm_inventory=""
if ! tpm_inventory="$(sudo systemd-cryptenroll --tpm2-device=list 2>&1)"; then
  stop "could not inspect TPM2 devices: $tpm_inventory"
fi
printf '\nTPM2 devices (required for automatic root unlock):\n%s\n' "$tpm_inventory"
tpm_device_count=0
while IFS= read -r tpm_line; do
  if [[ "$tpm_line" =~ /dev/tpm(rm)?[[:digit:]]+ ]]; then
    tpm_device_count=$((tpm_device_count + 1))
  fi
done <<<"$tpm_inventory"
[[ "$tpm_device_count" == 1 ]] || stop "expected exactly one usable TPM2 device, found $tpm_device_count; check firmware settings before installing"

disko_rev=""
if ! disko_rev="$(nix --extra-experimental-features "nix-command flakes" eval --raw --impure --expr '(builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.disko.locked.rev')"; then
  stop 'could not resolve the Disko revision from flake.lock'
fi
[[ "$disko_rev" =~ ^[[:xdigit:]]{40}$ ]] || stop "flake.lock contains an invalid Disko revision: $disko_rev"

printf '\nWARNING: the next command permanently destroys the partition table and all data on %s.\n' "$disk"
printf '%s\n' 'This clean-install wipe is intentional and cannot be undone.'
printf '%s\n' 'Do not continue unless the disk, GPU, UEFI, and backup checks are correct.'
read -r -p "Type exactly 'WIPE $disk AS $host' to continue: " wipe_confirmation || stop 'wipe confirmation was not answered'
[[ "$wipe_confirmation" == "WIPE $disk AS $host" ]] || stop 'exact wipe confirmation did not match; no destructive command was run'

disko_ref="github:nix-community/disko/$disko_rev"
printf 'Using pinned Disko revision %s from flake.lock.\n' "$disko_rev"
sudo nix --extra-experimental-features "nix-command flakes" run "$disko_ref" -- \
  --mode destroy,format,mount --flake ".#$host"

readonly luks_partition="/dev/disk/by-partlabel/cryptroot"
[[ -b "$luks_partition" ]] || stop "Disko did not create the expected LUKS partition '$luks_partition'"
luks_parent="$(lsblk -dnro PKNAME -- "$luks_partition" 2>/dev/null || true)"
luks_parent="${luks_parent//$'\n'/}"
luks_parent="${luks_parent//[[:space:]]/}"
[[ -n "$luks_parent" ]] || stop "could not identify the parent disk for '$luks_partition'"
[[ "/dev/$luks_parent" == "$disk" ]] || stop "LUKS partition '$luks_partition' belongs to /dev/$luks_parent, not '$disk'"

printf '\nEnroll TPM2 automatic unlock for %s.\n' "$luks_partition"
printf '%s\n' 'Enter the same LUKS passphrase that Disko requested during formatting.'
sudo systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrs= \
  "$luks_partition"
if ! sudo systemd-cryptenroll "$luks_partition" | grep -qw tpm2; then
  stop 'TPM2 enrollment could not be verified; the encrypted disk remains accessible with its LUKS passphrase'
fi
printf '%s\n' 'TPM2 enrollment verified.'

sudo nixos-install --flake ".#$host"
sudo nixos-enter --root "/mnt" -c "passwd kevin"

printf '\nEncrypted install, TPM2 enrollment, and interactive password setup completed.\n'
printf '%s\n' 'Reboot manually when ready:'
printf '%s\n' '  sudo reboot'
