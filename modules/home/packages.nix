{ pkgs, ... }:
let
  paperweight = pkgs.callPackage ../../packages/paperweight.nix { };
  splayer-next = pkgs.callPackage ../../packages/splayer-next.nix { };
in
{
  # Nix packages to install to $HOME
  #
  # Search for packages here: https://search.nixos.org/packages
  home.packages = with pkgs; [
    claude-code
    codex
    omnix
    opencode

    # Desktop applications
    bitwarden-desktop
    bolt-launcher
    brave
    code-cursor
    ente-auth
    firefox
    github-desktop
    gnome-calendar
    gnome-disk-utility
    lmstudio
    mission-center
    nautilus
    obsidian
    netbird-ui
    paperweight
    papers
    proton-authenticator
    proton-pass
    proton-vpn
    protonmail-bridge-gui
    protonmail-desktop
    runelite
    signal-desktop
    splayer-next
    telegram-desktop
    # Official Discord client with the Vencord mod injected (replaces vesktop).
    (discord.override { withVencord = true; })
    vicinae
    vscodium

    # Unix tools
    age
    ansible
    bitwarden-cli
    cloudflared
    crane
    fluxcd
    gh
    go-task
    helmfile
    kubeconform
    kubecolor
    kubectl
    kubernetes-helm
    kustomize
    minijinja
    mise
    ranger # Terminal file manager
    ripgrep # Better `grep`
    fd
    sd
    sops
    stern
    talhelper
    talosctl
    terraform
    tree
    gnumake
    yamllint
    yq-go
    proton-pass-cli
    _1password-cli

    # Nix dev
    cachix
    nil # Nix language server
    nix-info
    nixpkgs-fmt


    # On ubuntu, we need this less for `man home-configuration.nix`'s pager to
    # work.
    less
  ];

  # Programs natively supported by home-manager.
  # They can be configured in `programs.*` instead of using home.packages.
  programs = {
    # Better `cat`
    bat.enable = true;
    # Type `<ctrl> + r` to fuzzy search your shell history
    fzf.enable = true;
    jq.enable = true;
    # Install btop https://github.com/aristocratos/btop
    btop.enable = true;
    # Better `ls` (mooniri zsh aliases in shell.nix invoke `eza` directly).
    eza.enable = true;
    # Tmate terminal sharing.
    tmate = {
      enable = true;
      #host = ""; #In case you wish to use a server other than tmate.io
    };
  };
}
