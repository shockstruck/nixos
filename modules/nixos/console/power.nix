# Physical power button: short press suspends to RAM with the running game
# still in memory (SteamOS-style quick resume), long press (logind's
# compiled 5s hold) powers off. Verified against source before writing:
#   nixos/modules/system/boot/systemd/logind.nix (this flake's locked
#     nixpkgs rev, b1b875982b17…), lines 13-40: `services.logind.settings.Login`
#     is the freeform option that reaches logind.conf's `[Login]` section;
#     lines 96-97: `services.logind.powerKey` / `powerKeyLongPress` are
#     `mkRenamedOptionModule` aliases of `HandlePowerKey` /
#     `HandlePowerKeyLongPress`, so the `settings.Login` form used below and
#     `configurations/nixos/laptop/power.nix`'s lid-switch keys are the same
#     mechanism. logind's compiled default for `HandlePowerKey` is
#     `poweroff`; ChimeraOS on generic (non-Deck) hardware overrides only
#     that key to `suspend` and nothing else
#     (ChimeraOS/chimeraos rootfs/etc/systemd/logind.conf.d/power_off.conf,
#     `main`) — the model followed here. Valve's Deck-only `powerbuttond`
#     daemon (Jovian-NixOS modules/steam/steam.nix, Bazzite's deck image) is
#     deliberately not used: it is not in nixpkgs and gates on
#     Jupiter/Galileo hardware in ChimeraOS gamescope-session's
#     device-quirks, neither of which applies to this AMD desktop-class box.
#
# Steam's own SteamOS power menu "Suspend" item is already shown (gamescope
# session args in ./session.nix include -steamos3/-steampal/-steamdeck) and
# already calls logind's Suspend over D-Bus with no config needed here.
# TV standby-before-sleep/wake-on-resume over HDMI-CEC and controller wake
# are already handled in ./cec.nix and ./input.nix respectively. This file
# is only the missing physical-button path.
{
  services.logind.settings.Login = {
    HandlePowerKey = "suspend";
    HandlePowerKeyLongPress = "poweroff";
  };
}
