{ lib
, stdenv
, cmake
, ninja
, pkg-config
, hyprland
, src
, ...
}:
# `src` and `hyprland` are explicit required arguments so the Home Manager
# module and the flake-level package override both bind the plugin to the
# flake-locked source and the exact configured Hyprland (`finalPackage`).
# There is no fallback fetch — the sole source authority is the
# `hypr-autoscroll` flake input pinned in `flake.lock`.
stdenv.mkDerivation (finalAttrs: {
  pname = "hypr-autoscroll";
  version = "0.1.2";
  inherit src;

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];

  # Build against the exact Hyprland package plus its own buildInputs so the
  # `hyprland` pkg-config module (which requires aquamarine and the rest of
  # the Hyprland dependency closure) resolves. Mirrors nixpkgs'
  # `mkHyprlandPlugin` behaviour while keeping a plain `stdenv.mkDerivation`.
  buildInputs = [
    hyprland
  ] ++ hyprland.buildInputs or [ ];

  # Build the CTest target (test-scroll-math) and run it.
  doCheck = true;

  # Upstream's CMake target uses `PREFIX ""`, so the SHARED artifact is
  # installed as `$out/lib/hypr-autoscroll.so`. Home Manager resolves a
  # plugin package at `${package}/lib/lib${pname}.so`, so rename the
  # artifact to the expected `libhypr-autoscroll.so`.
  postInstall = ''
    mv $out/lib/hypr-autoscroll.so $out/lib/libhypr-autoscroll.so
  '';

  meta = {
    homepage = "https://github.com/estebanhiram/hypr-autoscroll";
    description = "Windows-style middle-click autoscrolling for Hyprland";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
})
