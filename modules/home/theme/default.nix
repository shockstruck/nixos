# Aggregates the theme modules. Picked up by the parent auto-importer
# (modules/home/default.nix maps every entry, so `./theme` resolves here).
{
  imports = [
    ./eldritch.nix
    ./mactahoe.nix
  ];
}
