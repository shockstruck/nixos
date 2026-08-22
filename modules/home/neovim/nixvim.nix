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
      };
      extensions = {
        file-browser.enable = true;
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
  ];
}
