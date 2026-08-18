{ flake
, lib
, pkgs
, ...
}:
let
  initialSettings = pkgs.writeText "dms-initial-settings.json" (builtins.toJSON {
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

    clockFormat = "12h";
    clockDateFormat = "ddd, MM/dd";
    lockDateFormat = "dddd, MMMM d";
    showSeconds = false;
    padHours12Hour = false;

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
          "battery"
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
      $DRY_RUN_CMD mkdir -p "$settingsDir"

      if [[ ! -e "$settingsDir/settings.json" ]]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 ${initialSettings} "$settingsDir/settings.json"
      fi

      if [[ ! -e "$settingsDir/plugin_settings.json" ]]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 ${initialPluginSettings} "$settingsDir/plugin_settings.json"
      fi

      if [[ ! -e "$HOME/.config/xdg-terminals.list" ]]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 ${initialTerminal} "$HOME/.config/xdg-terminals.list"
      fi
    '';

    home.packages = with pkgs; [
      easyeffects
      nwg-displays
      ollama
      kdePackages.dolphin
      kdePackages.systemsettings
    ];

    services.easyeffects.enable = true;
  };
}
