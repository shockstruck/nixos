{ pkgs, ... }:
let
  paperweight = pkgs.callPackage ../../packages/paperweight.nix { };
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
    code-cursor
    ente-auth
    firefox
    github-desktop
    gnome-calendar
    gnome-disk-utility
    lmstudio
    looking-glass-client
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
    telegram-desktop
    # Official Discord client with the Vencord mod injected (replaces vesktop).
    (discord.override { withVencord = true; })
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
    jq.enable = true;
    # Install btop https://github.com/aristocratos/btop
    btop.enable = true;
    # Tmate terminal sharing.
    tmate = {
      enable = true;
      #host = ""; #In case you wish to use a server other than tmate.io
    };
  };
}
