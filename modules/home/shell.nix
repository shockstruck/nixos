{ config, lib, ... }:
{
  home.activation.migrateZshHistory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    oldHistory="${config.home.homeDirectory}/.zsh_history"
    newHistory="${config.xdg.configHome}/zsh/.zsh_history"

    if [[ -f "$oldHistory" && ! -e "$newHistory" ]]; then
      $DRY_RUN_CMD mkdir -p "$(dirname "$newHistory")"
      $DRY_RUN_CMD mv "$oldHistory" "$newHistory"
    fi
  '';

  programs = {
    atuin = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      flags = [ "--disable-up-arrow" ];
      settings = {
        auto_sync = false;
        enter_accept = false;
        filter_mode = "global";
        inline_height = 30;
        search_mode = "fuzzy";
        show_preview = true;
        style = "compact";
        update_check = false;
      };
    };

    # on macOS, you probably don't need this
    bash = {
      enable = true;
      initExtra = ''
        # Custom bash profile goes here
      '';
    };

    # For macOS's default shell.
    zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      enableCompletion = true;
      envExtra = ''
        # Custom ~/.zshenv goes here
      '';
      profileExtra = ''
        # Custom ~/.zprofile goes here
      '';
      loginExtra = ''
        # Custom ~/.zlogin goes here
      '';
      logoutExtra = ''
        # Custom ~/.zlogout goes here
      '';
    };

    # Type `z <pat>` to cd to some directory
    zoxide.enable = true;

    # Atuin owns Ctrl-R; fzf keeps its file and directory widgets.
    fzf.historyWidget.command = "";

    # Better shell prompt!
    starship = {
      enable = true;
      settings = {
        username = {
          style_user = "blue bold";
          style_root = "red bold";
          format = "[$user]($style) ";
          disabled = false;
          show_always = true;
        };
        hostname = {
          ssh_only = false;
          ssh_symbol = "🌐 ";
          format = "on [$hostname](bold red) ";
          trim_at = ".local";
          disabled = false;
        };
      };
    };
  };
}
