# Verified against nixpkgs source before writing:
#   nixos/modules/programs/steam.nix:
#     gamescopeSession.enable — a submodule option under programs.steam.
#     protontricks.enable — lib.mkEnableOption "protontricks, a simple
#       wrapper for running Winetricks commands for Proton-enabled games".
#     protontricks.package — lib.mkPackageOption pkgs "protontricks"; the
#       module applies `.override { inherit extraCompatPaths; }` to it.
#     extraPackages (listOf package, default [ ]) — folded into the FHS
#       env's `extraPkgs`, so a package listed here lands on Steam's own
#       PATH inside its bubblewrap sandbox, not the host's.
#     gamescopeSession.steamArgs (listOf str, default [ "-tenfoot"
#       "-pipewire-dmabuf" ]) — appended after `-- steam` in the
#       `steam-gamescope` wrapper's `gamescope --steam ${args} -- steam
#       ${steamArgs}` invocation, i.e. these are the Steam client's own CLI
#       args, distinct from `gamescopeSession.args` (gamescope's own args).
#       The default's `-tenfoot` is desktop Big Picture; overridden below to
#       the SteamOS gaming-mode flag set instead.
#   pkgs/development/interpreters/python/hooks/pytest-check-hook.sh:
#     disabledTests is turned into a pytest `-k` deselect expression.
#   nixos/modules/services/display-managers/greetd.nix:
#     settings.initial_session is referenced directly by the module
#     (`default = !(cfg.settings ? initial_session);`); settings is a
#     freeform submodule passed through to greetd's TOML config, so
#     default_session is the standard companion key from greetd's own
#     schema rather than a separately declared nix option.
#   nixos/modules/services/desktops/pipewire/pipewire.nix:
#     enable, alsa.enable, alsa.support32Bit, pulse.enable all declared.
#   nixos/modules/security/rtkit.nix: enable declared.
#   nixos/modules/services/desktops/flatpak.nix: asserts xdg.portal.enable.
#   nixos/modules/config/xdg/portal.nix: enable, extraPortals (asserted
#     non-empty when enabled), config (attrsOf (attrsOf (str | listOf str))).
#   nixos/modules/programs/gamescope.nix: capSysNice (bool, default false) —
#     when true, config wraps the package in `security.wrappers.gamescope`
#     (cap_sys_nice+pie) and drops it from environment.systemPackages, so
#     `gamescope` on PATH resolves to the capability-wrapped copy.
#   nixos/modules/programs/steam.nix: `programs.gamescope.enable = lib.mkDefault
#     cfg.gamescopeSession.enable;` and `steam-gamescope` is a writeShellScriptBin
#     that calls plain `gamescope --steam ...` (resolved via PATH, so it picks
#     up the wrapper above). gamescopeSession.args (listOf str, default [ ])
#     is a submodule option passed straight to that `gamescope` invocation.
#   nixos/modules/programs/wayland/hyprland.nix:
#     `security.wrappers.Hyprland.capabilities = "cap_sys_nice+ep"` — `+ep`
#     (effective+permitted), not `+pie` like gamescope's own wrapper above:
#     no inheritable bit, so the capability does not propagate into anything
#     Hyprland execs. Steam's own bwrap sandbox under a Hyprland session is
#     therefore unaffected, unlike the ambient `+pie` gamescope wrapper this
#     file deliberately leaves off.
#     `programs.hyprland.package` (mkPackageOption's `apply` composes in
#     XWayland support) is the final package the module itself execs via the
#     `security.wrappers.Hyprland` wrapper above; `lib.getExe' pkg "hyprctl"`
#     (nixpkgs lib `meta.nix`) resolves the same package's `hyprctl` by store
#     path, since `steamos-session-select gamescope` is called from a
#     systemd --user service (Noctalia's "Return to Gaming Mode" launcher)
#     whose PATH cannot be relied on to contain it.
#   hyprwm/Hyprland v0.56.2 (the nixpkgs package version at the pinned rev):
#     `start-hyprland` (start/, installed to bin/ unconditionally by the root
#     CMakeLists) is the watchdog wrapper the upstream `hyprland.desktop`
#     session execs. It forks the compositor with `--watchdog-fd` and, when
#     that fd is absent, `CCompositor` posts the "Hyprland was started
#     without start-hyprland" overlay notification on every start
#     (src/Compositor.cpp, TXT_KEY_NOTIF_NO_WATCHDOG, unless
#     `misc:disable_watchdog_warning`). `--path` (start/src/main.cpp) sets
#     the binary it `execvp`s (start/src/core/Instance.cpp), so pointing it
#     at the security wrapper keeps cap_sys_nice. On a clean compositor exit
#     (`hyprctl dispatch exit`) it returns 0; on a crash it relaunches
#     Hyprland in safe mode itself instead of returning here.
#
# Session-switch contract: Steam's Big Picture "Switch to Desktop" runs
# `steamos-session-select plasma|desktop` from inside its own FHS env and
# waits for that call to end the current session — this is the SteamOS /
# Bazzite / Jovian convention, not a NixOS-specific API. `steamos-session-select`
# below records the requested next session in a file under $XDG_RUNTIME_DIR
# (visible on both sides of Steam's bwrap sandbox, since buildFHSEnv bind-mounts
# every top-level dir of `/` including `/run`) and runs `steam -shutdown`, which
# ends the running Steam client; gamescope then exits because Steam is its
# primary child. `console-session` is the loop greetd execs instead of running
# `steam-gamescope` once: it reads that file to decide whether to start the
# Hyprland/Noctalia session or go back to gamescope, and only hands control
# back to greetd when nothing asked for a switch.
{ config, lib, pkgs, ... }:

let
  sessionSelect = pkgs.writeShellApplication {
    name = "steamos-session-select";
    runtimeInputs = [ pkgs.coreutils pkgs.procps ];
    text = ''
      state="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/console-session-next"

      case "''${1:-}" in
        desktop | plasma | plasma-wayland | plasma-x11 | plasma-wayland-persistent | plasma-x11-persistent)
          # The persistent variants are treated as one-shot here: this host
          # has no separate "always land in desktop" mode to persist into,
          # only the per-switch record below.
          printf 'desktop\n' > "$state"
          if command -v steam > /dev/null 2>&1; then
            # Inside the FHS env this is Steam's own launcher; ending the
            # running client here is what makes gamescope exit.
            steam -shutdown || true
          else
            pkill -TERM -u "$(id -u)" -x gamescope || true
          fi
          ;;
        gamescope)
          printf 'gamescope\n' > "$state"
          if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
            ${lib.getExe' config.programs.hyprland.package "hyprctl"} dispatch exit
          fi
          ;;
        *)
          echo "usage: steamos-session-select desktop|plasma|gamescope" >&2
          exit 1
          ;;
      esac
    '';
  };

  returnToGamingMode = pkgs.makeDesktopItem {
    name = "return-to-gaming-mode";
    desktopName = "Return to Gaming Mode";
    exec = "steamos-session-select gamescope";
    icon = "steam";
    categories = [ "Game" ];
  };

  consoleSession = pkgs.writeShellApplication {
    name = "console-session";
    runtimeInputs = [ pkgs.coreutils pkgs.procps ];
    text = ''
      state="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/console-session-next"
      # Stale request from an earlier boot; XDG_RUNTIME_DIR does not survive
      # a reboot, but defend against a crashed session leaving it behind.
      rm -f "$state"

      while true; do
        next="gamescope"
        if [ -f "$state" ]; then
          next="$(cat "$state")"
          rm -f "$state"
        fi

        if [ "$next" = "desktop" ]; then
          echo "console-session: switch to desktop requested, waiting for steam to close"
          for _ in $(seq 1 30); do
            pgrep -u "$(id -u)" -x steam > /dev/null 2>&1 || break
            sleep 1
          done
          echo "console-session: starting desktop session"
          # Through the watchdog, not the bare wrapper: without it every
          # desktop session opens on Hyprland's "started without
          # start-hyprland" warning (header note). --path keeps the
          # cap_sys_nice wrapper as the binary the watchdog execs.
          ${lib.getExe' config.programs.hyprland.package "start-hyprland"} \
            --path ${config.security.wrapperDir}/Hyprland || true
          echo "console-session: desktop session ended"
          continue
        fi

        echo "console-session: starting gamescope session"
        # Asserts Steam's default compat tool while Steam is not running;
        # defined in ./launchers.nix.
        ${config.system.path}/bin/steam-compat-default || true
        ${config.system.path}/bin/steam-gamescope || true
        echo "console-session: gamescope session ended"

        if [ -f "$state" ]; then
          continue
        fi

        echo "console-session: no switch requested, handing back to greetd"
        exit 0
      done
    '';
  };
in

{
  # Deliberately off. capSysNice replaces gamescope with a
  # security.wrappers copy whose wrapper raises cap_sys_nice into the
  # *ambient* set (nixos/modules/security/wrappers/wrapper.c,
  # make_caps_ambient) so the real binary can use it. Ambient capabilities
  # survive execve into every descendant, and gamescope does not drop them
  # before spawning its child (src/Utils/Process.cpp). pkgs.steam is a
  # buildFHSEnv, so that child is bubblewrap, and bwrap refuses to start as
  # an unprivileged user holding capabilities (bubblewrap.c acquire_privs:
  # "Unexpected capabilities but not setuid"). Steam exits at once, gamescope
  # shuts down after its primary child, and greetd loops back to the
  # greeter. Cost of leaving it off: gamescope logs "No CAP_SYS_NICE, falling
  # back to regular-priority compute and threads" and runs its compositor
  # threads at normal priority.
  programs.gamescope.capSysNice = false;

  programs.steam = {
    enable = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];
    protontricks.enable = true;
    # extraCompatPackages makes the steam module rebuild protontricks with a
    # non-default extraCompatPaths, so it is never in the binary cache and CI
    # compiles it on a GitHub runner whose single-user Nix cannot sandbox.
    # There, upstream's test_flatpak_xdg_user_dir writes a `#!/bin/bash` shim
    # using `[[ ]]` that ends up interpreted by the host's dash and fails
    # (`xdg-user-dir: 2: [[: not found`). The same suite passes in Hydra's
    # sandbox; nothing in this host's config is involved. Deselect that one
    # test and keep the other 169.
    protontricks.package = pkgs.protontricks.overrideAttrs (prev: {
      disabledTests = (prev.disabledTests or [ ]) ++ [ "test_flatpak_xdg_user_dir" ];
    });
    gamescopeSession.enable = true;
    # gamescope's own MangoHud overlay (spawns mangoapp inside the session),
    # the SteamOS/Bazzite way of getting the HUD in a gamescope session.
    gamescopeSession.args = [ "--mangoapp" ];
    # Under gamescope the client shows the SteamOS-style power menu because
    # it checks IN_GAMESCOPE, but the "Switch to Desktop" action only calls
    # steamos-session-select when the client was ALSO started with
    # -steamos3 (ON_STEAMOS) — without it the button is wired to nothing and
    # sits on "Switching to desktop…" forever (ValveSoftware/steam-for-linux
    # issue 11241; every working gamescope-session setup — ChimeraOS/Bazzite,
    # Jovian, the AUR steamos-session-select package — starts Steam this
    # way). Known side effects of pretending to be SteamOS 3: Settings →
    # System's OS-update check fails looking for steamos-update /
    # steamos-select-branch polkit helpers this host doesn't ship (a
    # harmless "command not found" in the journal), and the desktop-style
    # Shift+Tab overlay shortcut is replaced by the controller Guide-button
    # behaviour.
    #
    # -gamepadui -steamos3 -steampal -steamdeck is the full SteamOS
    # gaming-mode flag set: Valve's own steam-launcher (jupiter's
    # gamescope-session), ChimeraOS's gamescope-session-steam
    # (sessions.d/steam, CLIENTCMD=…) and Bazzite (80-bazzite.just, same
    # CLIENTCMD) all start Steam this way. -gamepadui replaces -tenfoot
    # (desktop Big Picture) with the SteamOS home / gamepad UI — the
    # Deck-style Quick Access Menu and the Steam-menu sidebar on the Guide
    # button live only inside it, not in Big Picture. -pipewire-dmabuf is
    # kept from the nixpkgs default. -steamdeck's trade-off: some games pick
    # their Deck graphics preset (lower textures) on first launch, since it
    # presents the machine as a Steam Deck; Bazzite ships a toggle for
    # exactly this — drop just this one flag if it bites on the 7900 XT.
    gamescopeSession.steamArgs = [ "-gamepadui" "-steamos3" "-steampal" "-steamdeck" "-pipewire-dmabuf" ];
    # steamos-session-select is what Big Picture's "Switch to Desktop" calls
    # from inside Steam's own FHS env; without it the call hangs forever.
    extraPackages = [ sessionSelect ];
  };

  # steamos-session-select also needs to be reachable outside Steam's FHS
  # env: the Hyprland session's "Return to Gaming Mode" launcher calls it
  # directly, and console-session below execs the desktop session it selects.
  environment.systemPackages = [ sessionSelect returnToGamingMode ];

  # initial_session boots straight into Steam once; when Steam exits without
  # requesting a switch, greetd falls to default_session, a text greeter
  # that relaunches Steam on login instead of crash-looping the autologin.
  # console-session is the loop that decides, on every exit, whether to come
  # back as gamescope, hand off to the Hyprland/Noctalia desktop, or (when
  # nothing requested a switch) return control to greetd — see the header
  # contract comment.
  #
  # greetd hands the session's stdout/stderr to the VT it owns (greetd
  # session/worker.rs, term_connect_pipes), so nothing gamescope, Steam or
  # Hyprland prints survives the session ending — the screen is cleared
  # before the greeter redraws. systemd-cat execs the session with both
  # streams on the journal instead (`journalctl -t steam-gamescope`); stdin
  # stays the VT.
  services.greetd =
    let
      session = "${config.systemd.package}/bin/systemd-cat -t steam-gamescope ${lib.getExe consoleSession}";
    in
    {
      enable = true;
      settings = {
        initial_session = {
          command = session;
          user = builtins.head config.myusers;
        };
        default_session = {
          command = "${lib.getExe pkgs.tuigreet} --cmd '${session}'";
          user = "greeter";
        };
      };
    };

  # The desktop gets audio through its own gui module; the console has no gui
  # module, so it needs its own pipewire/rtkit stack.
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;

  hardware.bluetooth.enable = true;
  services.flatpak.enable = true;
  security.polkit.enable = true;
  programs.dconf.enable = true;

  # services.flatpak asserts xdg.portal.enable. The Hyprland session brought
  # in by ./desktop.nix supplies its own hyprland-specific portal config
  # (programs.hyprland's configPackages) and xdg-desktop-portal prefers the
  # XDG_CURRENT_DESKTOP-specific file over the common default, so Big
  # Picture (which sets no XDG_CURRENT_DESKTOP) keeps this generic GTK
  # backend and the desktop session gets its own.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = [ "gtk" ];
  };
}
