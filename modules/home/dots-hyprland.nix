{ config
, flake
, lib
, pkgs
, ...
}:
let
  # The fork's module expects an upstream-style `.config` tree, while its
  # current branch stores the maintained Quickshell implementation in configs/.
  source = pkgs.runCommand "dots-hyprland-config-source" { } ''
    mkdir -p $out/.config
    cp -R ${flake.inputs.dots-hyprland}/configs/matugen $out/.config/matugen
    cp -R ${flake.inputs.dots-hyprland}/configs/quickshell $out/.config/quickshell
    chmod -R u+w $out/.config
    patch -d $out/.config/quickshell -p1 < ${../../patches/dots-hyprland-functional-fixes.patch}
  '';

  initialGreenTheme = pkgs.writeShellScript "dots-hyprland-initial-theme" ''
    set -euo pipefail

    generated="$HOME/.local/state/quickshell/user/generated"
    colors="$generated/colors.json"
    marker="$generated/.nix-theme-B6D086-dark-tonal-spot"
    if [[ -e "$marker" ]]; then
      exit 0
    fi

    for _ in {1..20}; do
      [[ -x "$HOME/.config/quickshell/ii/scripts/colors/switchwall.sh" ]] && break
      sleep 1
    done

    "$HOME/.config/quickshell/ii/scripts/colors/switchwall.sh" \
      --color '#B6D086' \
      --mode dark \
      --type scheme-tonal-spot

    test -s "$colors"
    touch "$marker"
  '';
in
{
  imports = [ flake.inputs.dots-hyprland.homeManagerModules.default ];

  config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    programs.dots-hyprland = {
      enable = true;
      inherit source;
      packageSet = "all";
      mode = "hybrid";

      # Preserve the fork's complete Config.qml, including its dock and AI/voice
      # schema. Its generated Nix replacement currently omits those settings.
      configuration = {
        enable = true;
        copyMiscConfig = false;
        copyFishConfig = false;
        copyHyprlandConfig = false;
      };

      touchegg.enable = true;
    };

    # The fork's hybrid activation backs up unrelated mutable configs, tries to
    # regenerate vendored qmldir files through store links, and copies an
    # optional reset helper before its ~/.local/bin setup runs.
    home.activation.copyQuickshellConfigs = lib.mkForce (
      lib.hm.dag.entryBefore [ "linkGeneration" ] ""
    );
    home.activation.generateQmldirFiles = lib.mkForce (
      lib.hm.dag.entryAfter [ "linkGeneration" ] ""
    );
    home.activation.createWorkingQsScript = lib.mkForce (
      lib.hm.dag.entryAfter [ "linkGeneration" ] ""
    );

    # switchwall.sh reads the KDE and application theme templates from this
    # path, but the fork's configuration module does not expose its new layout.
    xdg.configFile."matugen" = {
      source = "${source}/.config/matugen";
      recursive = true;
      force = true;
    };

    # quickshell-startup otherwise runs the writable-mode setup path even when
    # the module is configured in hybrid mode.
    home.activation.ensureDotsHyprlandSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p "$HOME/.cache/dots-hyprland"
      $DRY_RUN_CMD touch "$HOME/.cache/dots-hyprland/setup-complete"
      $DRY_RUN_CMD mkdir -p "$HOME/.config/hypr/custom/scripts"
      $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user unset-environment LD_LIBRARY_PATH || true

      shellConfig="$HOME/.config/illogical-impulse/config.json"
      if [[ -f "$shellConfig" ]]; then
        $DRY_RUN_CMD ${pkgs.bash}/bin/bash -c "${pkgs.jq}/bin/jq '.bar.workspaces.monochromeIcons = false | .dock.monochromeIcons = false' \"\$1\" > \"\$1.tmp\" && mv \"\$1.tmp\" \"\$1\"" _ "$shellConfig"
      fi
    '';

    # packageSet = "all" still omits several executables used by the complete
    # shell, capture, OCR, wallpaper, AI, and settings surfaces.
    home.packages = with pkgs; [
      bibata-cursors
      brightnessctl
      ddcutil
      easyeffects
      espeak-ng
      ffmpeg
      grim
      hyprshot
      imagemagick
      libcava
      libnotify
      libqalculate
      mpvpaper
      ollama
      piper-tts
      slurp
      socat
      songrec
      swappy
      tesseract
      (wf-recorder.override { ffmpeg = ffmpeg_8; })
      wl-screenrec
      wtype
      kdePackages.dolphin
      kdePackages.plasma-browser-integration
      kdePackages.plasma-systemmonitor
      kdePackages.systemsettings
    ];

    # The Python environment is only needed by shell scripts. Exporting its
    # library path session-wide breaks wrapped applications such as Electron.
    home.sessionVariables.LD_LIBRARY_PATH = lib.mkForce null;

    services.cliphist = {
      enable = true;
      systemdTargets = [ "hyprland-session.target" ];
    };

    services.easyeffects.enable = true;
    services.polkit-gnome.enable = true;

    # The target wants Quickshell, so ordering Quickshell after that same target
    # creates a systemd transaction cycle during Home Manager activation.
    systemd.user.services.quickshell.Unit = {
      After = lib.mkForce [ "graphical-session.target" ];
      Wants = lib.mkForce [ ];
    };

    services.hypridle = {
      enable = true;
      systemdTarget = "hyprland-session.target";
      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "hyprctl dispatch dpms on";
        };
        listener = [
          {
            timeout = 150;
            on-timeout = "brightnessctl -s set 10";
            on-resume = "brightnessctl -r";
          }
          {
            timeout = 300;
            on-timeout = "loginctl lock-session";
          }
          {
            timeout = 330;
            on-timeout = "hyprctl dispatch dpms off";
            on-resume = "hyprctl dispatch dpms on";
          }
          {
            timeout = 1800;
            on-timeout = "systemctl suspend";
          }
        ];
      };
    };

    systemd.user.services.dots-hyprland-initial-theme = {
      Unit = {
        Description = "Generate the initial green illogical-impulse theme";
        After = [ "quickshell.service" ];
        PartOf = [ "hyprland-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = initialGreenTheme;
        Environment = [
          "PATH=${config.home.profileDirectory}/bin:/run/wrappers/bin:/run/current-system/sw/bin"
        ];
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };
  };
}
