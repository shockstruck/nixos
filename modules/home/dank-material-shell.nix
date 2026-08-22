{ config
, flake
, lib
, osConfig
, pkgs
, ...
}:
let
  isLaptop = osConfig.networking.hostName == "laptop";
  ollamaPackage = if isLaptop then pkgs.ollama-cuda else pkgs.ollama-rocm;
  sharedPluginIds = [
    "calculator"
    "claudeCodeUsage"
    "dankKDEConnect"
    "dockerManager"
    "quickCapture"
    "sathiAi"
    "wallpaperCarousel"
  ];
  enabledPluginIds = sharedPluginIds ++ lib.optional isLaptop "netbirdStatus";
  requiredRightWidgets = [
    "dockerManager"
    "claudeCodeUsage"
  ] ++ lib.optional isLaptop "netbirdStatus";
  defaultControlCenterWidgets = [
    { id = "volumeSlider"; enabled = true; width = 50; }
    { id = "brightnessSlider"; enabled = true; width = 50; }
    { id = "wifi"; enabled = true; width = 50; }
    { id = "bluetooth"; enabled = true; width = 50; }
    { id = "audioOutput"; enabled = true; width = 50; }
    { id = "audioInput"; enabled = true; width = 50; }
    { id = "nightMode"; enabled = true; width = 50; }
    { id = "darkMode"; enabled = true; width = 50; }
  ];
  requiredControlCenterWidgets = [
    { id = "plugin_quickCapture"; enabled = true; width = 50; }
    { id = "plugin_dankKDEConnect"; enabled = true; width = 50; }
  ] ++ lib.optional isLaptop { id = "plugin_netbirdStatus"; enabled = true; width = 50; };

  requiredSettingsFilter = ''
    .useFahrenheit = true
    | .useAutoLocation = false
    | .showSeconds = true
    | .showWorkspaceApps = true
    | .groupWorkspaceApps = true
    | .groupActiveWorkspaceApps = true
    | .launcherLogoMode = "os"
    | .dockLauncherEnabled = true
    | .dockLauncherLogoMode = "os"
    | .dockShowTrash = true
    | .cursorSettings.theme = "Adwaita"
    | .cursorSettings.size = 24
    | .loginctlLockIntegration = false
    | .lockBeforeSuspend = false
    | .acLockTimeout = 0
    | .batteryLockTimeout = 0
    | .acMonitorTimeout = 0
    | .batteryMonitorTimeout = 0
    | .acSuspendTimeout = 0
    | .batterySuspendTimeout = 0
    | .barConfigs = (
        (.barConfigs // [])
        | map(
            if .id == "default" then
              .leftWidgets = (
                (.leftWidgets // [])
                | if index("launcherButton") then . else ["launcherButton"] + . end
              )
              | .rightWidgets = (
                  (.rightWidgets // [])
                  | reduce ${(builtins.toJSON (requiredRightWidgets ++ lib.optional isLaptop "battery"))}[] as $widget (.;
                      if index($widget) then . else . + [$widget] end
                    )
                )
            else . end
          )
      )
    | .controlCenterWidgets = (
        (.controlCenterWidgets // ${builtins.toJSON defaultControlCenterWidgets})
        | reduce ${builtins.toJSON requiredControlCenterWidgets}[] as $widget (.;
            if any(.[]; .id == $widget.id) then . else . + [$widget] end
          )
      )
  '';
  requiredSettingsFilterFile = pkgs.writeText "dms-required-settings.jq" requiredSettingsFilter;
  requiredPluginSettingsFilter = lib.concatStringsSep "\n| " (
    map (pluginId: ".${pluginId}.enabled = true") enabledPluginIds
  );
  requiredPluginSettingsFilterFile = pkgs.writeText "dms-required-plugin-settings.jq" requiredPluginSettingsFilter;

  initialSettings = pkgs.writeText "dms-initial-settings.json" (builtins.toJSON {
    configVersion = 13;
    # Idle + locking are owned by stasis + swaylock (SHOA-1002). Zeroing
    # DMS's idle timeouts and disabling its loginctl lock integration hands
    # the locker role entirely to swaylock so the two idle managers do not
    # fight (see modules/home/idle.nix + swaylock.nix).
    acLockTimeout = 0;
    batteryLockTimeout = 0;
    acMonitorTimeout = 0;
    batteryMonitorTimeout = 0;
    acSuspendTimeout = 0;
    batterySuspendTimeout = 0;
    lockBeforeSuspend = false;
    loginctlLockIntegration = false;

    fontFamily = "Google Sans Flex";
    monoFontFamily = "JetBrainsMono Nerd Font";

    showDock = true;
    dockAutoHide = true;
    dockSmartAutoHide = true;
    dockGroupByApp = true;
    dockLauncherEnabled = true;
    dockLauncherLogoMode = "os";
    dockShowTrash = true;

    showWorkspaceApps = true;
    groupWorkspaceApps = true;
    groupActiveWorkspaceApps = true;
    launcherLogoMode = "os";
    cursorSettings = {
      theme = "Adwaita";
      size = 24;
    };

    clockFormat = "12h";
    clockDateFormat = "ddd, MM/dd";
    lockDateFormat = "dddd, MMMM d";
    showSeconds = true;
    padHours12Hour = false;
    useFahrenheit = true;
    useAutoLocation = false;

    currentThemeName = "green";
    currentThemeCategory = "generic";
    matugenScheme = "scheme-tonal-spot";

    notificationOverlayEnabled = true;
    notificationFocusedMonitor = true;

    barConfigs = [
      {
        id = "default";
        name = "Main Bar";
        enabled = true;
        position = 0;
        screenPreferences = [ "all" ];
        showOnLastDisplay = true;
        leftWidgets = [ "launcherButton" "workspaceSwitcher" "focusedWindow" ];
        centerWidgets = [ "music" "clock" "weather" ];
        rightWidgets = [
          "systemTray"
          "clipboard"
          "cpuUsage"
          "memUsage"
          "sathiAi"
          "notificationButton"
        ] ++ requiredRightWidgets ++ lib.optional isLaptop "battery" ++ [
          "controlCenterButton"
        ];
        spacing = 4;
        innerPadding = 4;
        barInsetPadding = -1;
        bottomGap = 0;
        transparency = 1.0;
        widgetTransparency = 1.0;
        squareCorners = false;
        noBackground = false;
        maximizeWidgetIcons = false;
        maximizeWidgetText = false;
        removeWidgetPadding = false;
        widgetPadding = 8;
        gothCornersEnabled = false;
        gothCornerRadiusOverride = false;
        gothCornerRadiusValue = 12;
        borderEnabled = false;
        borderColor = "surfaceText";
        borderOpacity = 1.0;
        borderThickness = 1;
        widgetOutlineEnabled = false;
        widgetOutlineColor = "primary";
        widgetOutlineOpacity = 1.0;
        widgetOutlineThickness = 1;
        fontScale = 1.0;
        iconScale = 1.0;
        autoHide = false;
        autoHideStrict = false;
        autoHideDelay = 250;
        showOnWindowsOpen = false;
        openOnOverview = false;
        visible = true;
        popupGapsAuto = true;
        popupGapsManual = 4;
        maximizeDetection = true;
        useOverlayLayer = false;
        scrollEnabled = true;
        scrollXBehavior = "column";
        scrollYBehavior = "workspace";
        shadowIntensity = 0;
        shadowOpacity = 60;
        shadowColorMode = "default";
        shadowCustomColor = "#000000";
        clickThrough = false;
        hoverPopouts = false;
        hoverPopoutDelay = 150;
      }
    ];
  });

  initialSession = pkgs.writeText "dms-initial-session.json" (builtins.toJSON {
    configVersion = 3;
    weatherLocation = "Detroit, MI";
    weatherCoordinates = "42.3314,-83.0458";
  });

  initialPluginSettings = pkgs.writeText "dms-initial-plugin-settings.json" (builtins.toJSON ({
    sathiAi = {
      enabled = true;
      customProviders = [
        {
          id = "local-ollama";
          type = "openai";
          name = "Ollama";
          credential = "";
          url = "http://127.0.0.1:11434";
          useGrounding = false;
          modelFilter = "";
        }
      ];
      systemPrompt = "You are a helpful assistant. Answer concisely.";
      persistChatHistory = true;
    };
  } // lib.genAttrs enabledPluginIds (_: { enabled = true; })));

  initialTerminal = pkgs.writeText "xdg-terminals.list" ''
    kitty.desktop
  '';
in
{
  imports = [
    flake.inputs.dank-material-shell.homeModules.dank-material-shell
    flake.inputs.dank-material-shell.homeModules.niri
    flake.inputs.dms-plugin-registry.homeModules.default
  ];

  config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    programs.dank-material-shell = {
      enable = true;
      systemd = {
        enable = true;
        # niri satisfies graphical-session.target (niri-flake user services
        # bind to it); this replaces the Hyprland-specific
        # hyprland-session.target.
        target = "graphical-session.target";
      };

      # DankMaterialShell first-class niri integration. `includes.enable`
      # rewrites ~/.config/niri/config.kdl to `include` DMS's matugen-driven
      # theme files (dms/*.kdl, regenerated at runtime) plus the settings
      # this repo authors in modules/home/niri.nix (niri/hm.kdl). DMS's own
      # keybind include ("binds") is dropped from the include set because
      # modules/home/niri.nix owns the binds (niri rejects duplicates); for
      # the same reason `enableKeybinds` stays off. `enableSpawn` stays off —
      # DMS is started via systemd (below), not niri spawn-at-startup, so it
      # is not double-launched.
      niri = {
        enableKeybinds = false;
        enableSpawn = false;
        includes = {
          enable = true;
          filesToInclude = [
            "alttab"
            "colors"
            "cursor"
            "layout"
            "outputs"
            "windowrules"
            "wpblur"
          ];
        };
      };

      enableSystemMonitoring = true;
      enableVPN = true;
      enableDynamicTheming = true;
      enableAudioWavelength = true;
      enableCalendarEvents = true;

      # Keep plugin state writable so plugin preferences can be changed from
      # DMS settings after activation enforces the enabled plugin set.
      managePluginSettings = false;
      plugins = {
        sathiAi.enable = true;
        calculator.enable = true;
        claudeCodeUsage.enable = true;
        dankKDEConnect.enable = true;
        dockerManager.enable = true;
        quickCapture.enable = true;
        wallpaperCarousel.enable = true;
      } // lib.optionalAttrs isLaptop {
        netbirdStatus.enable = true;
      };
    };

    # DMS scans directories only, so create real plugin directories with
    # recursively linked files instead of one symlink per directory.
    xdg.configFile =
      lib.genAttrs
        (map (pluginId: "DankMaterialShell/plugins/${pluginId}") enabledPluginIds)
        (_: {
          force = true;
          recursive = true;
        })
      // {
        "mimeapps.list".force = true;
      };

    home.activation.migrateDankMaterialShellPluginLinks =
      lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
        pluginsDir="$HOME/.config/DankMaterialShell/plugins"
        for pluginId in ${lib.escapeShellArgs enabledPluginIds}; do
          pluginPath="$pluginsDir/$pluginId"
          if [[ -L "$pluginPath" ]]; then
            $DRY_RUN_CMD rm "$pluginPath"
          fi
        done
      '';

    systemd.user.services.dms.Unit.X-Restart-Triggers =
      map
        (pluginId: toString config.programs.dank-material-shell.plugins.${pluginId}.src)
        enabledPluginIds;

    # DMS owns these files after first activation. Home Manager only supplies
    # workstation defaults when no mutable settings exist yet.
    home.activation.seedDankMaterialShell = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settingsDir="$HOME/.config/DankMaterialShell"
      stateDir="''${XDG_STATE_HOME:-$HOME/.local/state}/DankMaterialShell"
      $DRY_RUN_CMD mkdir -p "$settingsDir"
      $DRY_RUN_CMD mkdir -p "$stateDir"

      if [[ ! -e "$settingsDir/settings.json" ]]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 ${initialSettings} "$settingsDir/settings.json"
      fi

      if [[ ! -e "$settingsDir/plugin_settings.json" ]]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 ${initialPluginSettings} "$settingsDir/plugin_settings.json"
      fi

      if [[ ! -e "$stateDir/session.json" ]]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 ${initialSession} "$stateDir/session.json"
      fi

      $DRY_RUN_CMD ${pkgs.bash}/bin/bash -c '
        set -euo pipefail
        ${pkgs.jq}/bin/jq --from-file ${requiredSettingsFilterFile} "$1" > "$1.tmp"
        chmod 0600 "$1.tmp"
        mv "$1.tmp" "$1"
      ' _ "$settingsDir/settings.json"

      $DRY_RUN_CMD ${pkgs.bash}/bin/bash -c '
        set -euo pipefail
        ${pkgs.jq}/bin/jq --from-file ${requiredPluginSettingsFilterFile} "$1" > "$1.tmp"
        chmod 0600 "$1.tmp"
        mv "$1.tmp" "$1"
      ' _ "$settingsDir/plugin_settings.json"

      $DRY_RUN_CMD ${pkgs.bash}/bin/bash -c '
        set -euo pipefail
        ${pkgs.jq}/bin/jq ".weatherLocation = \"Detroit, MI\" | .weatherCoordinates = \"42.3314,-83.0458\"" "$1" > "$1.tmp"
        chmod 0600 "$1.tmp"
        mv "$1.tmp" "$1"
      ' _ "$stateDir/session.json"

      # DankMaterialShell's niri theme includes (~/.config/niri/dms/*.kdl) are
      # generated by DMS + matugen at runtime and wired via the DMS niri
      # module's `includes` (see the `niri` block above), so no static
      # per-compositor seeding is needed here (the Hyprland build seeded
      # ~/.config/hypr/dms/*.lua from embedded files).

      if [[ ! -e "$HOME/.config/xdg-terminals.list" ]]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 ${initialTerminal} "$HOME/.config/xdg-terminals.list"
      fi
    '';

    home.activation.restartDankMaterialShell =
      lib.hm.dag.entryAfter [ "reloadSystemd" "seedDankMaterialShell" ] ''
        $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user try-restart dms.service || true
      '';

    home.packages = with pkgs; [
      curl
      easyeffects
      imagemagick
      img2pdf
      nautilus
      ollamaPackage
      qt6.qt5compat
      sshfs
      tesseract
      zbar
    ];

    xdg.mimeApps = {
      enable = true;
      defaultApplications."inode/directory" = "org.gnome.Nautilus.desktop";
    };
    xdg.dataFile."applications/mimeapps.list".force = true;

    services.easyeffects.enable = true;
  };
}
