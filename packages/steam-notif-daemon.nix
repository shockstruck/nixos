# steam_notif_daemon — a minimal `org.freedesktop.Notifications` server that
# forwards *other* applications' XDG desktop notifications into Steam's
# overlay. It does not render Steam's own toasts (downloads, invites, ...):
# Steam draws those itself in the gamepad UI. On `Notify` it runs
# `<steam> -ifrunning steam://open_xdg_notification/?...` and on
# `CloseNotification` the `steam://close_xdg_notification/?...` form
# (Jovian-Experiments/steam_notif_daemon `main.c`, tag v1.0.1). Without it
# nothing owns the notification D-Bus name while gamescope runs, so a
# `notify-send` from Heroic, Lutris, Sunshine, a Flatpak or a non-Steam game
# goes nowhere. SteamOS, ChimeraOS and Jovian all run it in the gamescope
# session; `modules/nixos/console/session.nix` runs it here.
#
# Upstream hard-codes `$HOME/.steam/root/ubuntu12_32/steam` as the binary to
# call. Jovian-NixOS (`pkgs/steam_notif_daemon/default.nix`) patches that to a
# store-path handler that runs the bootstrapped Steam binary inside nixpkgs'
# `steam-run` FHS env so `-ifrunning` reaches the running client
# (`pkgs/jovian-steam-protocol-handler/default.nix`). `handler.patch` is
# Jovian's `jovian.patch` verbatim and `steamHandler` below is the same
# handler. Pin, source hash and `-Dsd-bus-provider=libsystemd` follow that
# package; `libcurl` is only used for URL escaping.
#
# `steamRun`: the console module passes `config.programs.steam.package.run`
# (the steam-run FHS env of the configured Steam). It defaults to null so the
# flake's own `packages` output, which is evaluated without allowUnfree, does
# not pull unfree Steam into evaluation; with it unset (the bare flake output
# only) the handler resolves `steam-run` from PATH.
#
# Update path: bump `version` (the tag is `v${version}`) and re-hash `src`;
# re-check `handler.patch` still applies against the new `main.c`.
{ lib
, stdenv
, fetchFromGitHub
, replaceVars
, writeShellScript
, meson
, ninja
, pkg-config
, systemd
, curl
, steamRun ? null
}:
let
  steamRunExe =
    if steamRun == null
    then "steam-run"
    else lib.getExe' steamRun "steam-run";

  steamHandler = writeShellScript "steam-notif-daemon-handler" ''
    exec ${steamRunExe} "$HOME/.steam/root/ubuntu12_32/steam" "$@"
  '';
in
stdenv.mkDerivation (finalAttrs: {
  pname = "steam-notif-daemon";
  version = "1.0.1";

  src = fetchFromGitHub {
    owner = "Jovian-Experiments";
    repo = "steam_notif_daemon";
    rev = "v${finalAttrs.version}";
    hash = "sha256-mtG2D+FEzTtYi3XnFKifhHLC5h8ApB2XREn74AVCbWc=";
  };

  patches = [
    (replaceVars ./steam-notif-daemon/handler.patch {
      handler = "${steamHandler}";
    })
  ];

  mesonFlags = [ "-Dsd-bus-provider=libsystemd" ];

  nativeBuildInputs = [ pkg-config meson ninja ];
  buildInputs = [ systemd curl ];

  meta = {
    description = "Forwards XDG desktop notifications into Steam's overlay";
    homepage = "https://github.com/Jovian-Experiments/steam_notif_daemon";
    license = lib.licenses.mit;
    mainProgram = "steam_notif_daemon";
    platforms = [ "x86_64-linux" ];
  };
})
