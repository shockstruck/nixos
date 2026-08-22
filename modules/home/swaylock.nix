# swaylock — the workstation's overall screen locker (SHOA-993).
#
# Wayland-specific adaptation of the mooniri rice
# (github:revaljonathan/mooniri, `config/swaylock/config`), themed to the
# Tokyo Night Moon palette to stay consistent with the terminal refactor
# (SHOA-991). mooniri's locker uses swaylock-effects extensions (`clock`,
# `indicator-radius`, `indicator-thickness`), so we install
# `swaylock-effects` rather than upstream swaylock.
#
# `services.swayidle` (see idle.nix) is what invokes this on idle,
# before-sleep, and on any `loginctl lock-session` — making swaylock the
# single, effective locker. NixOS PAM wiring for authentication lives in
# `modules/nixos/gui/niri.nix` (`security.pam.services.swaylock`);
# without it swaylock can lock but never unlock.
{ pkgs
, lib
, ...
}:
{
  config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    programs.swaylock = {
      enable = true;
      package = pkgs.swaylock-effects;

      # Adapted 1:1 from mooniri `config/swaylock/config`. The upstream
      # `ring-ver-color=82aaf` is a truncated 5-digit hex; corrected here to
      # the intended Tokyo Night Moon blue `82aaff`.
      settings = {
        show-failed-attempts = true;
        indicator-radius = 100;
        indicator-thickness = 7;

        # Matches the repo mono family (nerd-fonts.jetbrains-mono, SHOA-991/DMS).
        font = "JetBrainsMono Nerd Font";

        clock = true;
        timestr = "%H:%M:%S";
        datestr = "%a, %e of %B";

        color = "222436";
        bs-hl-color = "fca7ea";
        caps-lock-bs-hl-color = "fca7ea";
        caps-lock-key-hl-color = "c3e88d";
        inside-color = "222436";
        inside-clear-color = "222436";
        inside-caps-lock-color = "222436";
        inside-ver-color = "222436";
        inside-wrong-color = "222436";
        key-hl-color = "c3e88d";
        layout-bg-color = "00000000";
        layout-border-color = "00000000";
        layout-text-color = "c8d3f5";
        line-color = "00000000";
        line-clear-color = "00000000";
        line-caps-lock-color = "00000000";
        line-ver-color = "00000000";
        line-wrong-color = "00000000";
        ring-color = "2f334d";
        ring-clear-color = "fca7ea";
        ring-caps-lock-color = "ff966c";
        ring-ver-color = "82aaff";
        ring-wrong-color = "ff757f";
        separator-color = "00000000";
        text-color = "c8d3f5";
        text-clear-color = "fca7ea";
        text-caps-lock-color = "ff966c";
        text-ver-color = "82aaff";
        text-wrong-color = "ff757f";
      };
    };
  };
}
