{ flake
, lib
, osConfig
, pkgs
, ...
}:
let
  isLaptop = osConfig.networking.hostName == "laptop";
  ollamaPackage = if isLaptop then pkgs.ollama-cuda else pkgs.ollama-rocm;

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
    | .barConfigs = (
        (.barConfigs // [])
        | map(
            if .id == "default" then
              .leftWidgets = (
                (.leftWidgets // [])
                | if index("launcherButton") then . else ["launcherButton"] + . end
              )
              ${lib.optionalString isLaptop ''
                | .rightWidgets = (
                    (.rightWidgets // [])
                    | if index("battery") then . else . + ["battery"] end
                  )
              ''}
            else . end
          )
      )
  '';
  requiredSettingsFilterFile = pkgs.writeText "dms-required-settings.jq" requiredSettingsFilter;

  initialSettings = pkgs.writeText "dms-initial-settings.json" (builtins.toJSON {
    configVersion = 13;
    acLockTimeout = 300;
    batteryLockTimeout = 300;
    acMonitorTimeout = 330;
    batteryMonitorTimeout = 330;
    acSuspendTimeout = 1800;
    batterySuspendTimeout = 1800;
    lockBeforeSuspend = true;
    loginctlLockIntegration = true;

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
    matugenTemplateFoot = true;

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
        ] ++ lib.optional isLaptop "battery" ++ [
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

  initialOutputs = pkgs.writeText "dms-initial-outputs.lua" ''
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
  '';

  initialUserBinds = pkgs.writeText "dms-initial-user-binds.lua" ''
    -- Optional per-user keybind overrides managed by DMS.
  '';

  initialPluginSettings = pkgs.writeText "dms-initial-plugin-settings.json" (builtins.toJSON {
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
  });

  initialTerminal = pkgs.writeText "xdg-terminals.list" ''
    foot.desktop
  '';
in
{
  imports = [ flake.inputs.dank-material-shell.homeModules.dank-material-shell ];

  config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    programs.dank-material-shell = {
      enable = true;
      systemd = {
        enable = true;
        target = "hyprland-session.target";
      };

      enableSystemMonitoring = true;
      enableVPN = true;
      enableDynamicTheming = true;
      enableAudioWavelength = true;
      enableCalendarEvents = true;

      # Keep plugin state writable so providers and chat preferences can be
      # changed from DMS settings after the initial Ollama seed.
      managePluginSettings = false;
      plugins.sathiAi.src = flake.inputs.sathi-ai;
    };

    # DMS owns these files after first activation. Home Manager only supplies
    # workstation defaults when no mutable settings exist yet.
    home.activation.seedDankMaterialShell = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settingsDir="$HOME/.config/DankMaterialShell"
      stateDir="''${XDG_STATE_HOME:-$HOME/.local/state}/DankMaterialShell"
      hyprDmsDir="$HOME/.config/hypr/dms"
      $DRY_RUN_CMD mkdir -p "$settingsDir"
      $DRY_RUN_CMD mkdir -p "$stateDir"
      $DRY_RUN_CMD mkdir -p "$hyprDmsDir"

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
        ${pkgs.jq}/bin/jq ".weatherLocation = \"Detroit, MI\" | .weatherCoordinates = \"42.3314,-83.0458\"" "$1" > "$1.tmp"
        chmod 0600 "$1.tmp"
        mv "$1.tmp" "$1"
      ' _ "$stateDir/session.json"

      if [[ ! -e "$hyprDmsDir/colors.lua" ]]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 ${flake.inputs.dank-material-shell}/core/internal/config/embedded/hypr-colors.lua "$hyprDmsDir/colors.lua"
      fi
      if [[ ! -e "$hyprDmsDir/outputs.lua" ]]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 ${initialOutputs} "$hyprDmsDir/outputs.lua"
      fi
      if [[ ! -e "$hyprDmsDir/layout.lua" ]]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 ${flake.inputs.dank-material-shell}/core/internal/config/embedded/hypr-layout.lua "$hyprDmsDir/layout.lua"
      fi
      if [[ ! -e "$hyprDmsDir/cursor.lua" ]]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 ${flake.inputs.dank-material-shell}/core/internal/config/embedded/hypr-cursor.lua "$hyprDmsDir/cursor.lua"
      fi
      if [[ ! -e "$hyprDmsDir/binds-user.lua" ]]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 ${initialUserBinds} "$hyprDmsDir/binds-user.lua"
      fi
      if [[ ! -e "$hyprDmsDir/windowrules.lua" ]]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 ${flake.inputs.dank-material-shell}/core/internal/config/embedded/hypr-windowrules.lua "$hyprDmsDir/windowrules.lua"
      fi

      if [[ ! -e "$HOME/.config/xdg-terminals.list" ]]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 ${initialTerminal} "$HOME/.config/xdg-terminals.list"
      fi
    '';

    home.packages = with pkgs; [
      easyeffects
      nautilus
      ollamaPackage
    ];

    xdg.mimeApps = {
      enable = true;
      defaultApplications."inode/directory" = "org.gnome.Nautilus.desktop";
    };

    services.easyeffects.enable = true;
  };
}
