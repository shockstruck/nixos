# List of users for darwin or nixos system and their top-level configuration.
{ flake, pkgs, lib, config, ... }:
let
  inherit (flake.inputs) self;
  mapListToAttrs = m: f:
    lib.listToAttrs (map (name: { inherit name; value = f name; }) m);
in
{
  options = {
    myusers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "List of usernames";
      defaultText = "All users under ./configuration/users are included by default";
      default =
        let
          dirContents = builtins.readDir (self + /configurations/home);
          fileNames = builtins.attrNames dirContents; # Extracts keys: [ "kevin.nix" ]
          regularFiles = builtins.filter (name: dirContents.${name} == "regular") fileNames; # Filters for regular files
          baseNames = map (name: builtins.replaceStrings [ ".nix" ] [ "" ] name) regularFiles; # Removes .nix extension
        in
        baseNames;
    };
  };

  config = {
    # zsh must be enabled system-wide so it is added to /etc/shells and the
    # system /etc/zshrc + /etc/zprofile (Nix PATH / profile plumbing) are
    # generated. home-manager's programs.zsh.enable only writes the per-user
    # zsh config; it does NOT make zsh the login shell. Without this + the
    # per-user `shell` below, kitty (which inherits the login shell) opens bash
    # and the zsh + powerlevel10k config never loads (SHOA-1017).
    programs.zsh.enable = true;

    # For home-manager to work.
    # https://github.com/nix-community/home-manager/issues/4026#issuecomment-1565487545
    users.users = mapListToAttrs config.myusers (name:
      lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin
        {
          home = "/Users/${name}";
        } // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        isNormalUser = true;
        extraGroups = [ "wheel" "networkmanager" "video" "i2c" "docker" ];
        # Login shell -> zsh so kitty/login sessions get zsh + p10k, not bash.
        shell = pkgs.zsh;
      }
    );

    # Enable home-manager for our user
    home-manager.users = mapListToAttrs config.myusers (name: {
      imports = [ (self + /configurations/home/${name}.nix) ];
    });

    # All users can add Nix caches.
    nix.settings.trusted-users = [
      "root"
    ] ++ config.myusers;
  };
}
