{ config, lib, pkgs, ... }:
let
  # Eldritch palette source of truth (modules/home/theme/eldritch.nix, SHOA-999 C7).
  e = config.theme.eldritch;
in
{
  home.activation.migrateZshHistory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    oldHistory="${config.home.homeDirectory}/.zsh_history"
    newHistory="${config.xdg.configHome}/zsh/.zsh_history"
    if [[ -f "$oldHistory" && ! -e "$newHistory" ]]; then
      $DRY_RUN_CMD mkdir -p "$(dirname "$newHistory")"
      $DRY_RUN_CMD mv "$oldHistory" "$newHistory"
    fi
  '';
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    TERMINAL = "kitty";
    BAT_THEME = "tokyonight_moon";
    COLORTERM = "truecolor";
    MICRO_TRUECOLOR = "1";
    PDFVIEWER = "papers";
    IMAGEVIEWER = "imv";
    GOPATH = "${config.home.homeDirectory}/.go";
  };
  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"
    "${config.home.homeDirectory}/.cargo/bin"
    "${config.home.homeDirectory}/.go/bin"
  ];
  # Minimal, hand-curated powerlevel10k config. Keeps the same left/right prompt
  # elements (context, dir, vcs / status, command_execution_time, background_jobs,
  # time) recolored with the shared Eldritch palette (SHOA-997 C3, sourced from
  # config.theme.eldritch), with instant-prompt intentionally left off so no
  # p10k-instant-prompt cache sourcing snippet is required at the top of .zshrc.
  home.file.".p10k.zsh".text = ''
    # Lean-style powerlevel10k config -- NixOS-native equivalent of the upstream
    # `p10k configure` lean preset, recolored with the shared Eldritch palette
    # (config.theme.eldritch, modules/home/theme/eldritch.nix) in place of the
    # preset's 256-color defaults. Instant prompt is intentionally left off
    # so no top-of-.zshrc cache snippet is required.
    () {
      emulate -L zsh -o extended_glob
      unset -m '(POWERLEVEL9K_*|DEFAULT_USER)~POWERLEVEL9K_GITSTATUS_DIR'
      [[ $ZSH_VERSION == (5.<1->*|<6->.*) ]] || return
      # Two-line lean prompt: line 1 = context/dir/vcs (left) + status/time (right);
      # line 2 = the lean prompt char.
      typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(context dir vcs newline prompt_char)
      typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
        status
        command_execution_time
        background_jobs
        time
      )
      typeset -g POWERLEVEL9K_MODE=nerdfont-v3
      typeset -g POWERLEVEL9K_ICON_PADDING=none
      typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=true
      typeset -g POWERLEVEL9K_INSTANT_PROMPT=off
      typeset -g POWERLEVEL9K_TRANSIENT_PROMPT=always
      typeset -g POWERLEVEL9K_DISABLE_HOT_RELOAD=true
      # Lean look (upstream config/p10k-lean.zsh): transparent segment backgrounds,
      # no powerline separators, single-space subsegment separators, no surrounding
      # whitespace, and no multiline connectors.
      typeset -g POWERLEVEL9K_BACKGROUND=
      typeset -g POWERLEVEL9K_{LEFT,RIGHT}_{LEFT,RIGHT}_WHITESPACE=
      typeset -g POWERLEVEL9K_{LEFT,RIGHT}_SUBSEGMENT_SEPARATOR=' '
      typeset -g POWERLEVEL9K_{LEFT,RIGHT}_SEGMENT_SEPARATOR=
      typeset -g POWERLEVEL9K_ICON_BEFORE_CONTENT=true
      typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX=
      typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_PREFIX=
      typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_PREFIX=
      typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_SUFFIX=
      typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_SUFFIX=
      typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_SUFFIX=
      typeset -g POWERLEVEL9K_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=
      typeset -g POWERLEVEL9K_RIGHT_PROMPT_LAST_SEGMENT_END_SYMBOL=
      # Eldritch palette (config.theme.eldritch, modules/home/theme/eldritch.nix).
      typeset -g P10K_COLOR_TEXT="${e.foreground}"
      typeset -g P10K_COLOR_OVERLAY1="${e.comment}"
      typeset -g P10K_COLOR_BLUE="${e.blue}"
      typeset -g P10K_COLOR_LAVENDER="${e.purple}"
      typeset -g P10K_COLOR_SKY="${e.cyan}"
      typeset -g P10K_COLOR_TEAL="${e.green}"
      typeset -g P10K_COLOR_GREEN="${e.green}"
      typeset -g P10K_COLOR_YELLOW="${e.yellow}"
      typeset -g P10K_COLOR_PEACH="${e.orange}"
      typeset -g P10K_COLOR_RED="${e.red}"
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
      # Lean relies on prompt_char color for success/error, so the right-prompt
      # status icon is off for the plain OK/ERROR case.
      typeset -g POWERLEVEL9K_STATUS_OK=false
      typeset -g POWERLEVEL9K_STATUS_OK_FOREGROUND=$P10K_COLOR_GREEN
      typeset -g POWERLEVEL9K_STATUS_OK_VISUAL_IDENTIFIER_EXPANSION='✔'
      typeset -g POWERLEVEL9K_STATUS_ERROR=false
      typeset -g POWERLEVEL9K_STATUS_ERROR_FOREGROUND=$P10K_COLOR_RED
      typeset -g POWERLEVEL9K_STATUS_ERROR_VISUAL_IDENTIFIER_EXPANSION='✘'
      typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=3
      typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND=$P10K_COLOR_OVERLAY1
      typeset -g POWERLEVEL9K_BACKGROUND_JOBS_FOREGROUND=$P10K_COLOR_TEAL
      typeset -g POWERLEVEL9K_TIME_FOREGROUND=$P10K_COLOR_TEAL
      typeset -g POWERLEVEL9K_TIME_FORMAT='%D{%I:%M:%S %p}'
      typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_VIINS_FOREGROUND=$P10K_COLOR_GREEN
      typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_VIINS_FOREGROUND=$P10K_COLOR_RED
      typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_VIINS_CONTENT_EXPANSION='❯'
      typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_VIINS_CONTENT_EXPANSION='❯'
      # prompt_char sits alone on line 2: no connectors around it.
      typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=
      typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=
      (( ! $+functions[p10k] )) || p10k reload
    }
  '';
  # Single systemd-managed ssh-agent for the login session. Provides one
  # persistent agent + SSH_AUTH_SOCK so no per-shell `eval $(ssh-agent)` is
  # needed. Key loading is done by the zsh init hook below.
  services.ssh-agent.enable = true;
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
      # Powerlevel10k prompt.
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
          echo "\033[1;35mKernel $(uname -r)\033[0m"
          echo "\033[1;36m Shell $(echo $SHELL)"
          echo "\033[1;34m Disk $(df -B1G --output=size,used / | awk 'NR==2 {print $2 " GiB | " $1 " GiB"}')"
          echo "\033[0;32m Upt $(uptime -p|sed 's/^up //')"
          echo "\033[0;33m Host $(hostname)"
          echo ""
        }
        alias colmoon='palette'
        palette() {
          echo "\e[38;2;255;255;255m\e[48;2;34;36;54m bg #222436 \e[0m"
          echo "\e[38;2;255;255;255m\e[48;2;30;32;48m bg_dark #1e2030 \e[0m"
          echo "\e[38;2;26;26;46m\e[48;2;130;170;255m blue #82aaff \e[0m"
          echo "\e[38;2;26;26;46m\e[48;2;195;232;141m green #c3e88d \e[0m"
          echo "\e[38;2;26;26;46m\e[48;2;255;117;127m red #ff757f \e[0m"
          echo "\e[38;2;26;26;46m\e[48;2;255;199;119m yellow #ffc777 \e[0m"
          echo "\e[38;2;26;26;46m\e[48;2;255;150;108m orange #ff966c \e[0m"
          echo "\e[38;2;26;26;46m\e[48;2;192;153;255m magenta #c099ff \e[0m"
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
              *.tar.gz) tar xzf "$1" ;;
              *.bz2) bunzip2 "$1" ;;
              *.rar) unrar x "$1" ;;
              *.gz) gunzip "$1" ;;
              *.tar) tar xf "$1" ;;
              *.tbz2) tar xjf "$1" ;;
              *.tgz) tar xzf "$1" ;;
              *.zip) unzip "$1" ;;
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
        # Auto-load SSH keys into the persistent (systemd) agent.
        # Prefer ed25519 keys (GitHub default) then fall back to other private keys.
        # Idempotent: only adds keys that are not already in the agent.
        # Never prompts / blocks (SSH_ASKPASS=false) so p10k stays clean.
        () {
          emulate -L zsh
          [[ -o interactive ]] || return
          (( $+commands[ssh-add] )) || return

          # Collect keys already loaded (fingerprint list). Empty if agent is empty or unreachable.
          local -a loaded
          loaded=( ''${(f)"$(ssh-add -l 2>/dev/null)"} )

          local key
          # Prefer ed25519 first, then everything else that looks like a private key
          for key in ~/.ssh/id_ed25519(N.) ~/.ssh/id_ed25519_*(N.) ~/.ssh/*(N.); do
            case ''${key:t} in
              (*.pub|known_hosts*|config|authorized_keys*|environment|*.tmp*|*.old) continue ;;
            esac
            # Skip non-keys
            ssh-keygen -l -f "$key" >/dev/null 2>&1 || continue

            # Skip if this key’s fingerprint is already loaded
            local fp
            fp=$(ssh-keygen -l -f "$key" 2>/dev/null | awk '{print $2}')
            [[ -n $fp && $loaded[(I)*$fp*] -gt 0 ]] && continue

            # Silent add (no passphrase prompt, no output)
            SSH_ASKPASS=''${commands[false]} SSH_ASKPASS_REQUIRE=force DISPLAY= \
              ssh-add "$key" </dev/null >/dev/null 2>&1
          done
        }
      '';
    };
    # Type `z <pat>` to cd to some directory
    zoxide.enable = true;
    # Atuin owns Ctrl-R; fzf keeps its file and directory widgets.
    fzf.historyWidget.command = "";
  };
}
