{ config, lib, pkgs, ... }:
{
  home.activation.migrateZshHistory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    oldHistory="${config.home.homeDirectory}/.zsh_history"
    newHistory="${config.xdg.configHome}/zsh/.zsh_history"

    if [[ -f "$oldHistory" && ! -e "$newHistory" ]]; then
      $DRY_RUN_CMD mkdir -p "$(dirname "$newHistory")"
      $DRY_RUN_CMD mv "$oldHistory" "$newHistory"
    fi
  '';

  # mooniri exports (see modules/home/shell.nix history for the p10k/zsh
  # porting notes) -- EDITOR/VISUAL/TERMINAL/theme + viewer defaults.
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    TERMINAL = "kitty";
    BAT_THEME = "tokyonight_moon";
    COLORTERM = "truecolor";
    MICRO_TRUECOLOR = "1";
    PDFVIEWER = "zathura";
    IMAGEVIEWER = "imv";
    GOPATH = "${config.home.homeDirectory}/.go";
  };

  # mooniri PATH additions that still make sense on NixOS.
  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"
    "${config.home.homeDirectory}/.cargo/bin"
    "${config.home.homeDirectory}/.go/bin"
  ];

  # Minimal, hand-curated equivalent of mooniri's generated ~/.p10k.zsh
  # (that file is produced by `p10k configure` and is ~600 lines of mostly
  # default segment plumbing). This keeps the same left/right prompt
  # elements mooniri actually customized (context, dir, vcs / status,
  # command_execution_time, background_jobs, time) and the same
  # tokyonight-moon-derived palette, with instant-prompt intentionally left
  # off (see initExtra comment below) so no p10k-instant-prompt cache
  # sourcing snippet is required at the very top of .zshrc.
  home.file.".p10k.zsh".text = ''
    # Minimal powerlevel10k config -- NixOS-native equivalent of mooniri's
    # `p10k configure`-generated .p10k.zsh. See modules/home/shell.nix.
    () {
      emulate -L zsh -o extended_glob
      unset -m '(POWERLEVEL9K_*|DEFAULT_USER)~POWERLEVEL9K_GITSTATUS_DIR'
      [[ $ZSH_VERSION == (5.<1->*|<6->.*) ]] || return

      typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(context dir vcs)
      typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
        status
        command_execution_time
        background_jobs
        time
      )

      typeset -g POWERLEVEL9K_MODE=nerdfont-v3
      typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=true
      typeset -g POWERLEVEL9K_INSTANT_PROMPT=off
      typeset -g POWERLEVEL9K_TRANSIENT_PROMPT=always
      typeset -g POWERLEVEL9K_DISABLE_HOT_RELOAD=true

      # tokyonight-moon-derived palette (matches mooniri's .p10k.zsh)
      typeset -g P10K_COLOR_TEXT="#c8d3f5"
      typeset -g P10K_COLOR_OVERLAY1="#545c7e"
      typeset -g P10K_COLOR_BLUE="#82aaff"
      typeset -g P10K_COLOR_LAVENDER="#c099ff"
      typeset -g P10K_COLOR_SKY="#86e1fc"
      typeset -g P10K_COLOR_TEAL="#4fd6be"
      typeset -g P10K_COLOR_GREEN="#c3e88d"
      typeset -g P10K_COLOR_YELLOW="#ffc777"
      typeset -g P10K_COLOR_PEACH="#ff966c"
      typeset -g P10K_COLOR_RED="#ff757f"

      typeset -g POWERLEVEL9K_CONTEXT_FOREGROUND=$P10K_COLOR_PEACH
      typeset -g POWERLEVEL9K_CONTEXT_ROOT_FOREGROUND=$P10K_COLOR_YELLOW

      typeset -g POWERLEVEL9K_DIR_FOREGROUND=$P10K_COLOR_BLUE
      typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND=$P10K_COLOR_LAVENDER
      typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND=$P10K_COLOR_SKY
      typeset -g POWERLEVEL9K_DIR_ANCHOR_BOLD=true
      typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_unique
      typeset -g POWERLEVEL9K_SHORTEN_DIR_LENGTH=1

      typeset -g POWERLEVEL9K_VCS_CLEAN_FOREGROUND=$P10K_COLOR_GREEN
      typeset -g POWERLEVEL9K_VCS_UNTRACKED_FOREGROUND=$P10K_COLOR_GREEN
      typeset -g POWERLEVEL9K_VCS_MODIFIED_FOREGROUND=$P10K_COLOR_YELLOW
      typeset -g POWERLEVEL9K_VCS_BRANCH_ICON=$'\uF126 '

      typeset -g POWERLEVEL9K_STATUS_OK=true
      typeset -g POWERLEVEL9K_STATUS_OK_FOREGROUND=$P10K_COLOR_GREEN
      typeset -g POWERLEVEL9K_STATUS_OK_VISUAL_IDENTIFIER_EXPANSION='✔'
      typeset -g POWERLEVEL9K_STATUS_ERROR=true
      typeset -g POWERLEVEL9K_STATUS_ERROR_FOREGROUND=$P10K_COLOR_RED
      typeset -g POWERLEVEL9K_STATUS_ERROR_VISUAL_IDENTIFIER_EXPANSION='✘'

      typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=3
      typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND=$P10K_COLOR_OVERLAY1
      typeset -g POWERLEVEL9K_BACKGROUND_JOBS_FOREGROUND=$P10K_COLOR_TEAL
      typeset -g POWERLEVEL9K_TIME_FOREGROUND=$P10K_COLOR_TEAL
      typeset -g POWERLEVEL9K_TIME_FORMAT='%D{%H:%M:%S}'

      typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_VIINS_FOREGROUND=$P10K_COLOR_GREEN
      typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_VIINS_FOREGROUND=$P10K_COLOR_RED
      typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_VIINS_CONTENT_EXPANSION='❯'
      typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_VIINS_CONTENT_EXPANSION='❯'

      (( ! $+functions[p10k] )) || p10k reload
    }
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
      # Native home-manager autosuggestion/syntax-highlighting integration
      # is used instead of oh-my-zsh's `zsh-autosuggestions` /
      # `zsh-syntax-highlighting` plugins, so `oh-my-zsh.plugins` below only
      # loads `sudo` -- keeps both from being sourced twice.
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

      oh-my-zsh = {
        enable = true;
        plugins = [ "sudo" ];
      };

      # Powerlevel10k prompt, replacing starship (mooniri 1:1).
      #
      # `oh-my-zsh.theme` is intentionally left unset rather than pointed at
      # "powerlevel10k/powerlevel10k": the oh-my-zsh derivation doesn't
      # bundle that theme, so setting ZSH_THEME to it makes oh-my-zsh.sh
      # print a "theme not found" warning on every shell start. Instead the
      # theme is sourced as a `programs.zsh.plugins` entry, which
      # home-manager loads *after* oh-my-zsh.sh (initContent order 900 vs
      # oh-my-zsh's 800) and correctly overrides the prompt with no warning.
      plugins = [
        {
          name = "powerlevel10k";
          src = "${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k";
          file = "powerlevel10k.zsh-theme";
        }
      ];

      shellAliases = {
        ls = "eza -l -h --sort=modified --reverse --color=always --icons --git --group-directories-first";
        lss = "eza -l -h --sort=modified --reverse --color=always --icons --git --group-directories-first -G";
        la = "ls -A";
        lsa = "la -G";
        lt = "ls -T";
        x = "exit";
        c = "clear";
        nv = "nvim";
        vim = "nvim";
        y = "yazi";
        gs = "la && git status";
        sz = "du -sh * | sort -h";
        cd = "z";
        grep = "rg --color=auto --line-number --smart-case";
      };

      initExtra = ''
        setopt auto_cd
        setopt interactive_comments
        setopt multios
        setopt histexpand

        [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

        gf () {
          echo "\033[1;35mKernel  $(uname -r)\033[0m"
          echo "\033[1;36m Shell  $(echo $SHELL)"
          echo "\033[1;34m  Disk  $(df -B1G --output=size,used / | awk 'NR==2 {print $2 " GiB | " $1 " GiB"}')"
          echo "\033[0;32m   Upt  $(uptime -p|sed 's/^up //')"
          echo "\033[0;33m  Host  $(hostname)"
          echo ""
        }

        alias colmoon='palette'
        palette() {
          echo "\e[38;2;255;255;255m\e[48;2;34;36;54m bg  #222436                  \e[0m"
          echo "\e[38;2;255;255;255m\e[48;2;30;32;48m bg_dark  #1e2030             \e[0m"
          echo "\e[38;2;26;26;46m\e[48;2;130;170;255m blue  #82aaff                \e[0m"
          echo "\e[38;2;26;26;46m\e[48;2;195;232;141m green  #c3e88d               \e[0m"
          echo "\e[38;2;26;26;46m\e[48;2;255;117;127m red  #ff757f                 \e[0m"
          echo "\e[38;2;26;26;46m\e[48;2;255;199;119m yellow  #ffc777              \e[0m"
          echo "\e[38;2;26;26;46m\e[48;2;255;150;108m orange  #ff966c              \e[0m"
          echo "\e[38;2;26;26;46m\e[48;2;192;153;255m magenta  #c099ff             \e[0m"
        }

        gacp() {
          if [ -z "$1" ]; then
            echo "isi commit message dulu njinggs"
            return 1
          fi
          git add .
          git commit -m "$1"
          git push
        }

        take() {
          mkdir -p "$1" && cd "$1"
        }

        extract() {
          if [ -f "$1" ]; then
            case "$1" in
              *.tar.bz2) tar xjf "$1" ;;
              *.tar.gz)  tar xzf "$1" ;;
              *.bz2)     bunzip2 "$1" ;;
              *.rar)     unrar x "$1" ;;
              *.gz)      gunzip "$1" ;;
              *.tar)     tar xf "$1" ;;
              *.tbz2)    tar xjf "$1" ;;
              *.tgz)     tar xzf "$1" ;;
              *.zip)     unzip "$1" ;;
              *) echo "Format tolol." ;;
            esac
          else
            echo "mana filenya su."
          fi
        }

        weather() {
          curl wttr.in/"$1"
        }

        fuck() { sudo $(fc -ln -1) }
        f() { eval $(thefuck $(fc -ln -1)); }
      '';
    };

    # Type `z <pat>` to cd to some directory
    zoxide.enable = true;

    # Atuin owns Ctrl-R; fzf keeps its file and directory widgets.
    fzf.historyWidget.command = "";
  };
}
