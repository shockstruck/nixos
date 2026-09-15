# Neovim configuration managed using https://github.com/nix-community/nixvim
{
  # Theme
  colorschemes.tokyonight = {
    enable = true;
    settings.style = "moon";
  };

  # Settings
  opts = {
    expandtab = true;
    shiftwidth = 4;
    smartindent = true;
    tabstop = 4;
    softtabstop = 4;
    number = true;
    clipboard = "unnamedplus";
  };

  # Keymaps
  globals = {
    mapleader = " ";
  };

  plugins = {

    # UI
    web-devicons.enable = true;
    lualine.enable = true;
    bufferline.enable = true;
    treesitter.enable = true;
    which-key = {
      enable = true;
    };
    noice = {
      # WARNING: This is considered experimental feature, but provides nice UX
      enable = true;
      settings.presets = {
        bottom_search = true;
        command_palette = true;
        long_message_to_split = true;
        #inc_rename = false;
        #lsp_doc_border = false;
      };
    };
    telescope = {
      enable = true;
      keymaps = {
        "<leader>ff" = {
          options.desc = "file finder";
          action = "find_files";
        };
        "<leader>fg" = {
          options.desc = "find via grep";
          action = "live_grep";
        };
        "<leader>fb" = {
          options.desc = "buffers";
          action = "buffers";
        };
        "<leader>fr" = {
          options.desc = "recent files";
          action = "oldfiles";
        };
        "<leader>fh" = {
          options.desc = "help tags";
          action = "help_tags";
        };
        "<leader>fk" = {
          options.desc = "keymaps";
          action = "keymaps";
        };
        "<leader>fw" = {
          options.desc = "grep word under cursor";
          action = "grep_string";
        };
        "<leader>fd" = {
          options.desc = "diagnostics";
          action = "diagnostics";
        };
        "<leader>fs" = {
          options.desc = "document symbols";
          action = "lsp_document_symbols";
        };
        "<leader>fe" = {
          options.desc = "file browser";
          action = "file_browser";
        };
        "<leader>gc" = {
          options.desc = "git commits";
          action = "git_commits";
        };
        "<leader>gs" = {
          options.desc = "git status";
          action = "git_status";
        };
      };
      extensions = {
        file-browser.enable = true;
        fzf-native.enable = true;
        ui-select.enable = true;
      };
      settings.defaults = {
        file_ignore_patterns = [ "^.git/" ];
        sorting_strategy = "ascending";
        layout_config.prompt_position = "top";
      };
    };

    # Dev
    lsp = {
      enable = true;
      servers = {
        hls = {
          enable = true;
          installGhc = false; # Managed by Nix devShell
        };
        marksman.enable = true;
        nil_ls.enable = true;
        rust_analyzer = {
          enable = true;
          installCargo = false;
          installRustc = false;
        };
      };
    };
    lazygit.enable = true;

    # Editing QoL
    gitsigns.enable = true;
    todo-comments.enable = true;
    indent-blankline.enable = true;
    nvim-autopairs.enable = true;
    flash.enable = true;
    trouble.enable = true;
    blink-cmp = {
      enable = true;
      settings = {
        keymap.preset = "enter";
        completion.documentation.auto_show = true;
        signature.enabled = true;
      };
    };
    conform-nvim = {
      enable = true;
      autoInstall.enable = true;
      settings = {
        format_on_save = {
          lsp_format = "fallback";
          timeout_ms = 500;
        };
        formatters_by_ft = {
          nix = [ "nixpkgs_fmt" ];
          "_" = [ "trim_whitespace" ];
        };
      };
    };

    # Start screen (mirrors mooniri's snacks dashboard header; this nixvim
    # pin's `plugins.snacks` module has no `dashboard` sub-option, so
    # `plugins.alpha` is used as the equivalent start-screen plugin).
    alpha = {
      enable = true;
      settings.layout = [
        {
          type = "padding";
          val = 2;
        }
        {
          type = "text";
          val = [
            "███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗"
            "████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║"
            "██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║"
            "██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║"
            "██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║"
            "╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝"
            "Powered by LazyVim"
          ];
          opts = {
            position = "center";
            hl = "Keyword";
          };
        }
        {
          type = "padding";
          val = 2;
        }
        {
          type = "group";
          val = [
            {
              type = "button";
              val = "  New file";
              on_press.__raw = "function() vim.cmd[[ene]] end";
              opts.shortcut = "n";
            }
            {
              type = "button";
              val = "  Find file";
              on_press.__raw = "function() require('telescope.builtin').find_files() end";
              opts.shortcut = "f";
            }
            {
              type = "button";
              val = "  Quit Neovim";
              on_press.__raw = "function() vim.cmd[[qa]] end";
              opts.shortcut = "q";
            }
          ];
        }
      ];
    };
  };
  keymaps = [
    # Open lazygit within nvim. 
    {
      action = "<cmd>LazyGit<CR>";
      key = "<leader>gg";
    }
    {
      key = "<leader>xx";
      action = "<cmd>Trouble diagnostics toggle<cr>";
      options.desc = "diagnostics (Trouble)";
    }
    {
      key = "<leader>xX";
      action = "<cmd>Trouble diagnostics toggle filter.buf=0<cr>";
      options.desc = "buffer diagnostics (Trouble)";
    }
    {
      key = "<leader>cs";
      action = "<cmd>Trouble symbols toggle focus=false<cr>";
      options.desc = "symbols (Trouble)";
    }
    {
      key = "<leader>cf";
      action.__raw = ''function() require("conform").format({ lsp_format = "fallback" }) end'';
      mode = [
        "n"
        "v"
      ];
      options.desc = "format buffer/selection";
    }
    {
      key = "<leader>ft";
      action = "<cmd>TodoTelescope<cr>";
      options.desc = "todo comments";
    }
    {
      key = "s";
      action.__raw = ''function() require("flash").jump() end'';
      mode = [
        "n"
        "x"
        "o"
      ];
      options.desc = "flash jump";
    }
    {
      key = "S";
      action.__raw = ''function() require("flash").treesitter() end'';
      mode = [
        "n"
        "x"
        "o"
      ];
      options.desc = "flash treesitter";
    }
  ];
}
