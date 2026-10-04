# Limo as the console's Nexus Mods client and `nxm://` handler. Nexus Mods
# discontinued the official cross-platform Nexus Mods App in January 2026
# (nexusmods.com/news/15424); nixpkgs' `nexusmods-app` derivation already
# carries that fact as `meta.knownVulnerabilities`
# (pkgs/by-name/ne/nexusmods-app/package.nix), which nixpkgs refuses to
# evaluate without a `permittedInsecurePackages` exception, so it is not used
# here. Limo (`limo-app/limo`) is a native Qt5 mod manager with libloot built
# in, GPL-3.0+, packaged at nixpkgs `pkgs/by-name/li/limo/package.nix`
# (`pname = "limo"`, `version = "1.2.2"`) — unmaintained upstream since its
# last commit `ffdb4f9` (2025-05-03) but the least painful option available.
#
# Limo deploys mods by writing into the game's own directory rather than
# launching or wrapping the game, so it needs no Steam launch hook: titles
# started from Big Picture — native Steam games, and OGI or Heroic
# non-Steam shortcuts alike — pick up deployed mods with no change to
# `steam-tweaks`' compat-tool mapping or umu. It accepts any directory as a
# managed game, so OGI installs (not bought through a store) work the same
# as Steam/Heroic titles. Workflow: switch to this Hyprland/Noctalia desktop
# session, click a "Mod Manager Download" nxm link in Brave, Limo deploys,
# switch back to the gamescope session.
#
# `withUnrar` is left at its nixpkgs default of `false`
# (pkgs/by-name/li/limo/package.nix): turning it on pulls in the unfree
# `unrar`, which the public binary cache does not build, so Limo would
# compile from source on every rebuild. Limo's bundled libarchive already
# reads RAR4/RAR5; unrar is only a fallback for archives libarchive can't
# open.
#
# Upstream's `install_files/limo.desktop` (limo-app/limo @ v1.2.2) declares
# `MimeType=x-scheme-handler/nxm;` with `Exec=limo %u`, so setting it as the
# default `x-scheme-handler/nxm` handler here is enough for `nxm://` links
# to open in Limo once it is installed. `xdg.mimeApps.enable` and
# `defaultApplications` are home-manager's `modules/misc/xdg/mime-apps.nix`
# options; setting `enable = true` here merges cleanly with
# `modules/home/archives.nix`'s own `xdg.mimeApps.enable = true` (home-manager
# merges equal values for `types.bool` options) and its
# `defaultApplications` maps disjoint MIME keys (archive types, not `nxm`).
#
# Limo 1.2.2 leans on standard headers arriving transitively, which GCC 16's
# libstdc++ no longer does: the build stops at "'uint64_t' was not declared"
# (<cstdint>), then "'put_time' is not a member of 'std'" (<iomanip>), and the
# sources use more of the standard library the same way. Upstream is
# unmaintained, so every C++ translation unit force-includes the headers it
# relies on. The project is C++-only (`LANGUAGES CXX`), and a header that is
# already included is a no-op. `cmakeFlagsArray` keeps the space-separated
# value as a single flag.
{ lib, pkgs, ... }:
let
  forcedIncludes = [
    "algorithm"
    "array"
    "chrono"
    "cstdint"
    "functional"
    "iomanip"
    "limits"
    "memory"
    "optional"
    "sstream"
    "stdexcept"
  ];
  limo = pkgs.limo.overrideAttrs (prev: {
    preConfigure = (prev.preConfigure or "") + ''
      cmakeFlagsArray+=("-DCMAKE_CXX_FLAGS=${lib.concatMapStringsSep " " (h: "-include ${h}") forcedIncludes}")
    '';
  });
in
{
  home.packages = [ limo ];

  xdg.mimeApps = {
    enable = true;
    defaultApplications."x-scheme-handler/nxm" = "limo.desktop";
  };
}
