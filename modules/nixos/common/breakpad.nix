# breakpad 2024.02.16 no longer links on nixos-unstable: microdump_stackwalk
# links source_line_resolver_base.o, which references the FastSourceLineResolver
# Module vtable through module_factory.h's inline CreateModule, without
# fast_source_line_resolver.o. It reaches every host through
# protonmail-bridge-gui -> sentry-native -> breakpad (modules/home/packages.nix),
# so the overlay is shared; home-manager uses the system pkgs (nixos-unified
# sets home-manager.useGlobalPkgs).
#
# The vendored patch is the one proposed for nixpkgs in NixOS/nixpkgs#569323
# (carried from OpenEmbedded): it moves both CreateModule definitions out of
# line. Once nixpkgs ships its own fix-vtable-link.patch the guard below stops
# applying ours; drop this module and the patch then.
{ lib, ... }:
{
  nixpkgs.overlays = [
    (_final: prev: {
      breakpad = prev.breakpad.overrideAttrs (old: {
        patches =
          (old.patches or [ ])
          ++ lib.optional
            (!lib.any (p: lib.hasSuffix "fix-vtable-link.patch" (toString p)) (old.patches or [ ]))
            ./breakpad-fix-vtable-link.patch;
      });
    })
  ];
}
