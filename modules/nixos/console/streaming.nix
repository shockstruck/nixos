# Verified against nixpkgs source before writing:
#   nixos/modules/services/networking/sunshine.nix: enable, capSysAdmin,
#     openFirewall, autoStart all declared as `bool` options
#     (mkEnableOption / mkOption types.bool). The user unit
#     (`systemd.user.services.sunshine`) is `wantedBy = mkIf cfg.autoStart
#     [ "graphical-session.target" ]`.
{
  services.sunshine = {
    enable = true;
    capSysAdmin = true;
    openFirewall = true;
    autoStart = true;
  };

  # openFirewall opens Moonlight's ports on this host's own firewall only;
  # nothing on UniFi changes.
}
