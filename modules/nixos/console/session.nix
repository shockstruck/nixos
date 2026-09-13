# Verified against nixpkgs source before writing:
#   nixos/modules/programs/steam.nix:
#     gamescopeSession.enable — a submodule option under programs.steam.
#     protontricks.enable — lib.mkEnableOption "protontricks, a simple
#       wrapper for running Winetricks commands for Proton-enabled games".
#     protontricks.package — lib.mkPackageOption pkgs "protontricks"; the
#       module applies `.override { inherit extraCompatPaths; }` to it.
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
{ config, lib, pkgs, ... }:

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
  };

  # initial_session boots straight into Steam once; when Steam exits, greetd
  # falls to default_session, a text greeter that relaunches Steam on login
  # instead of crash-looping the autologin. steam-gamescope is the wrapper
  # nixpkgs installs into environment.systemPackages when
  # programs.steam.gamescopeSession.enable is true.
  #
  # greetd hands the session's stdout/stderr to the VT it owns (greetd
  # session/worker.rs, term_connect_pipes), so nothing gamescope or Steam
  # prints survives the session ending — the screen is cleared before the
  # greeter redraws. systemd-cat execs the session with both streams on the
  # journal instead (`journalctl -t steam-gamescope`); stdin stays the VT.
  services.greetd =
    let
      session = "${config.systemd.package}/bin/systemd-cat -t steam-gamescope ${config.system.path}/bin/steam-gamescope";
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

  # services.flatpak asserts xdg.portal.enable. On desktop/laptop
  # programs.hyprland turns the portal on and supplies its own backend; the
  # console has no compositor module, so it carries the generic GTK backend.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = [ "gtk" ];
  };
}
