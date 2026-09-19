# steamos-manager — Valve's daemon behind the Steam client's SteamOS-only
# settings (Quick Access "Performance" tab: GPU clock / power profile, TDP,
# CPU governor and scheduler; plus BIOS/dock updates and storage jobs on a
# Steam Deck). Two processes share one binary: `steamos-manager -r` on the
# system bus as root does the sysfs writes, `steamos-manager` on the session
# bus owns the public com.steampowered.SteamOSManager1 API the client talks
# to. Not in nixpkgs; consumed by modules/nixos/console/steamos-manager.nix,
# which declares both systemd units and the device config.
#
# Modelled on Jovian-Experiments/Jovian-NixOS pkgs/steamos-manager/default.nix
# (development branch, same tag): same src, build inputs and the two patches
# under ./steamos-manager/ (see their preambles for what was kept and
# dropped). Differences, all deliberate:
#   - `cargoLock.lockFile` with upstream's Cargo.lock vendored beside this
#     file instead of a `cargoHash`: a vendor hash cannot be computed on
#     the agent runtime (no `nix`), and the lock is all crates.io (217
#     packages at v26.4.1: 214 registry entries, 3 workspace path crates,
#     no git sources), so no `outputHashes` are needed. nixpkgs'
#     cargo-setup-hook diffs the source's Cargo.lock against the vendored
#     one, so the copy must stay byte-identical to upstream's at `version`.
#   - The systemd units are not installed from `data/`; the console module
#     declares them, so the `--device-config` flag the daemon accepts
#     (steamos-manager/src/bin/steamos-manager.rs, "bypasses DMI matching")
#     can be added there without drop-in overrides.
#   - No Steam Deck-only inputs (jupiter-hw-support, steamdeck-firmware,
#     jupiter-dock-updater-bin, jovian-stubs): platform.toml is installed as
#     upstream ships it, its /usr paths do not exist here, and every consumer
#     checks the script with `is_valid` (platform.rs) before registering the
#     interface, so those features simply stay off the bus.
#   - Binaries stay in $out/bin, where wrapGAppsNoGuiHook wraps them itself
#     (gio needs the gsettings schema path for the screen-reader settings).
#
# doCheck is off for the same reason as in Jovian: the test suite assumes
# Steam Deck hardware and FHS paths.
#
# Update path: `version` and `src.hash` are bumped by the weekly
# `nix-update` pass (.github/workflows/update-flake-lock.yaml) like every
# other package here; nix-update also refreshes `cargoLock.lockFile` from the
# new source. After a bump, re-check that both patches still apply — the
# hunks target upstream paths that move between releases.
{ coreutils
, dmidecode
, fetchFromGitLab
, glib
, gsettings-desktop-schemas
, iw
, iwd
, lib
, pkg-config
, replaceVars
, rustPlatform
, scx
, speechd-minimal
, trace-cmd
, udev
, wrapGAppsNoGuiHook
}:
rustPlatform.buildRustPackage rec {
  pname = "steamos-manager";
  version = "26.4.1";

  src = fetchFromGitLab {
    domain = "gitlab.steamos.cloud";
    owner = "holo";
    repo = "steamos-manager";
    tag = "v${version}";
    hash = "sha256-NVbYXZOd7+cUf0wDqptoHUBzHN/ukctcltir2axvAJo=";
  };

  cargoLock.lockFile = ./steamos-manager/Cargo.lock;

  # tests assume Steam Deck hardware and FHS paths
  doCheck = false;

  patches = [
    (replaceVars ./steamos-manager/hardcode-paths.patch {
      inherit coreutils dmidecode iw iwd;
      traceCmd = trace-cmd;
      # `scx.full` is what services.scx runs on this host by default
      # (nixos/modules/services/scheduling/scx.nix), so the path
      # CpuSchedulerManager::is_supported probes is already in the closure;
      # starting/stopping the scheduler goes through `scx.service`, not this
      # binary.
      scx = scx.full;
      out = null;
    })
    ./steamos-manager/disable-ftrace.patch
  ];

  postPatch = ''
    substituteInPlace \
      steamos-manager-macros/src/lib.rs \
      steamos-manager/src/daemon/root.rs \
      steamos-manager/src/daemon/user.rs \
      steamos-manager/src/hardware.rs \
      steamos-manager/src/platform.rs \
      --replace-fail "@out@" "$out"
  '';

  strictDeps = true;

  nativeBuildInputs = [
    glib
    pkg-config
    rustPlatform.bindgenHook
    wrapGAppsNoGuiHook
  ];

  buildInputs = [
    glib
    gsettings-desktop-schemas
    speechd-minimal
    udev
  ];

  # The subset of upstream's Makefile `install` target this host consumes,
  # with $(DESTDIR)/usr -> $out: D-Bus activation, policy and interface
  # files, the device configs (unused while the module passes
  # --device-config, kept so DMI matching still works if that flag is ever
  # dropped) and platform.toml.
  postInstall = ''
    install -Dm644 -t $out/share/dbus-1/system-services \
      data/system/com.steampowered.SteamOSManager1.service
    install -Dm644 -t $out/share/dbus-1/system.d \
      data/system/com.steampowered.SteamOSManager1.conf
    install -Dm644 -t $out/share/dbus-1/services \
      data/user/com.steampowered.SteamOSManager1.service
    install -Dm644 -t $out/share/dbus-1/interfaces data/interfaces/*.xml

    install -Dm644 -t $out/share/steamos-manager/devices data/devices/*.toml
    install -Dm644 -t $out/share/steamos-manager data/platform.toml
  '';

  meta = {
    description = "Daemon exposing SteamOS system settings to the Steam client over D-Bus";
    homepage = "https://gitlab.steamos.cloud/holo/steamos-manager";
    changelog = "https://gitlab.steamos.cloud/holo/steamos-manager/-/tags/v${version}";
    license = lib.licenses.mit;
    mainProgram = "steamosctl";
    platforms = [ "x86_64-linux" ];
  };
}
