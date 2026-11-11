# nixpkgs removed both of its Brave packages because their security
# updates had no committer to land them; Chromium is the
# nixpkgs-maintained replacement. The file keeps its name so
# `homeModules.brave` and the CI format-check path list stay unchanged.
{ ... }:
{
  programs.chromium = {
    enable = true;
    extensions = [
      { id = "nngceckbapebfimnlniiiahkandclblb"; } # Bitwarden
    ];
  };
}
