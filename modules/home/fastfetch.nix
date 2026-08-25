{ pkgs, config, ... }:
let
  # Mactahoe-default palette dark colors, source of truth
  # (modules/home/theme/mactahoe.nix, SHOA-1102).
  f = config.theme.mactahoe.dark;
in
{
  # Fastfetch with the NGR boxed layout + logo, ported from
  # s1devist1/my-linux-hp (SHOA-1058): config.jsonc structure + ngr1.txt logo
  # verbatim, packages row adapted to {nixpkgs} (NixOS, not pacman/flatpak),
  # and the Nord theme swapped to mactahoe-default palette hexes from
  # config.theme.mactahoe (SHOA-1102). The `noctalia` theme file has existed
  # since SHOA-1058 but was never referenced; `"theme": "noctalia"` below
  # activates it.
  home.packages = [ pkgs.fastfetch ];

  xdg.configFile."fastfetch/config.jsonc".text = ''
    {
      "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
      // Activate the noctalia theme file (defined since SHOA-1058 but never
      // referenced, so its hexes had no effect). Mactahoe-default palette colors,
      // SHOA-1102.
      "theme": "noctalia",
        "logo": {
        "type": "file",
        "source": "~/.config/fastfetch/ngr1.txt",
        "width": 28,
        "height": 16,
        "padding":{"left":3 , "top":4}
      },
      "display": {
        "separator": " ",
        "size": {
          "maxPrefix": "GB",
          "spaceBeforeUnit": "always",
          "binaryPrefix": "si"
        }
      },
      "modules": [
        // {
        //   "type": "custom",
        //   "format": "╭─────╮ ╭─────╮ ╭─────╮ ╭─╮ ╭─╮ ╭─╮ ╭─╮    ╭─────╮ ╭─────╮\n│ ╭───╯ │ ╭─╮ │ │ ╭───╯ │ │ │ │ │ │ │ │    │ ╭─╮ │ │ ╭───╯\n│ │     │ ╰─╯ │ │ │     │ ╰─╯ │ │ ╰─╯ │    │ │ │ │ │ ╰───╮\n│ │     │ ╭─╮ │ │ │     │ ╭─╮ │ ╰───╮ │    │ │ │ │ ╰───╮ │\n│ ╰───╮ │ │ │ │ │ ╰───╮ │ │ │ │ ╭───╯ │    │ ╰─╯ │ ╭───╯ │\n╰─────╯ ╰─╯ ╰─╯ ╰─────╯ ╰─╯ ╰─╯ ╰─────╯    ╰─────╯ ╰─────╯"
        // },
        // {
        //   "type": "custom",
        //   "format": "{#magenta}╭─────╮{#red} ╭─────╮{#yellow} ╭─────╮{#green} ╭─╮ ╭─╮{#cyan} ╭─╮ ╭─╮{#blue}   ╭─────╮{#white} ╭─────╮{#}\n{#magenta}│ ╭───╯{#red} │ ╭─╮ │{#yellow} │ ╭───╯{#green} │ │ │ │{#cyan} │ │ │ │{#blue}   │ ╭─╮ │{#white} │ ╭───╯{#}\n{#magenta}│ │    {#red} │ ╰─╯ │{#yellow} │ │    {#green} │ ╰─╯ │{#cyan} │ ╰─╯ │{#blue}   │ │ │ │{#white} │ ╰───╮{#}\n{#magenta}│ │    {#red} │ ╭─╮ │{#yellow} │ │    {#green} │ ╭─╮ │{#cyan} ╰───╮ │{#blue}   │ │ │ │{#white} ╰───╮ │{#}\n{#magenta}│ ╰───╮{#red} │ │ │ │{#yellow} │ ╰───╮{#green} │ │ │ │{#cyan} ╭───╯ │{#blue}   │ ╰─╯ │{#white} ╭───╯ │{#}\n{#magenta}╰─────╯{#red} ╰─╯ ╰─╯{#yellow} ╰─────╯{#green} ╰─╯ ╰─╯{#cyan} ╰─────╯{#blue}   ╰─────╯{#white} ╰─────╯{#}\n"
        // },
            {
      "type": "custom",
      "format": "\n\n"
    },
        {
          "type": "custom",
          "key": "╭───────────╮"
        },
        {
          "type": "title",
          "key": "│ {#34}{#cyan}{icon} user    {#keys}│",
          "format": "{user-name-colored}@{host-name-colored}"
        },
        {
          "type": "os",
          "key": "│ {#34}{#cyan}{icon} distro  {#keys}│",
          "format": "{pretty-name}"
        },
        {
          "type": "kernel",
          "key": "│ {#35}{#cyan} kernel  {#keys}│",
          "format": "{release}"
        },

        {
          "type": "wm",
          "key": "│ {#36}{#green}󰇄 wm      {#keys}│",
          "format": "{pretty-name}"
        },
        {
          "type": "de",
          "key": "│ {#36}{#green}󰇄 desktop {#keys}│"
        },
        {
          "type": "terminal",
          "key": "│ {#31}{#green} term    {#keys}│",
          "format": "{pretty-name}"
        },
        {
          "type": "shell",
          "key": "│ {#32}{#green} shell   {#keys}│",
          "format": "{pretty-name}"
        },
            {
          "type": "packages",
          "key": "\u2502 {#33}{#yellow}\uf0e7 packages {#keys}\u2502",
          "format": "{nixpkgs}"
        },
        {
          "type": "cpu",
          "key": "│ {#33}{#red}󰍛 cpu     {#keys}│",
          // "showPeCoreCount": true
          "format": "{name}"
        },
        {
          "type": "gpu",
          "key": "│ {#35}{#red}󰢮 gpu     {#keys}│",
          "hideType": "integrated",
          "format": "{1} {2}"
        },
        {
          "type": "memory",
          "key": "│ {#36}{#red} memory  {#keys}│",
          "format": "{used}  {#green}{#} {total}"
        },
        {
          "type": "disk",
          "key": "│ {#34}{#red} disk    {#keys}│",
          // "folders": "/"
          "format": "{size-used} {#red}{#} {size-total}"
        },
        {
          "type": "uptime",
          "key": "│ {#33}{#magenta}󰅐 uptime  {#keys}│"
        },
        {
          "type": "custom",
          "key": "│ {#39} colors  {#keys}│",
          "format": "{#black}{#} {#white}{#} {#red}{#} {#green}{#} {#yellow}{#} {#blue}{#} {#magenta}{#} {#cyan}{#} "
        },
        {
          "type": "custom",
          "key": "╰───────────╯"
        }
      ]
    }
  '';
  xdg.configFile."fastfetch/ngr1.txt".text = ''
    .__                          
    |__|  __ __  ______ ____     
    |  | |  |  \/  ___// __ \    
    |  | |  |  /\___ \\  ___/    
    |__| |____//____  >\___  >   
                    \/     \/    
                         .__     
    _____ _______   ____ |  |__  
    \__  \\_  __ \_/ ___\|  |  \ 
     / __ \|  | \/\  \___|   Y  \
    (____  /__|    \___  >___|  /
         \/            \/     \/ 
    ___.    __                   
    \_ |___/  |___  _  __        
     | __ \   __\ \/ \/ /        
     | \_\ \  |  \     /         
     |___  /__|   \/\_/          
         \/                      
  '';
  xdg.configFile."fastfetch/themes/noctalia.jsonc".text = ''
    {
      "logo": {
        "color": {
          "1": "${f.mPrimary}",
          "2": "${f.mTertiary}"
        }
      },
      "display": {
        "color": {
          "keys": "${f.mOnSurfaceVariant}",
          "title": "${f.mPrimary}"
        },
        "percent": {
          "color": {
            "green": "${f.terminal.normal.green}",
            "yellow": "${f.terminal.normal.yellow}",
            "red": "${f.mError}"
          }
        }
      }
    }
  '';
}
