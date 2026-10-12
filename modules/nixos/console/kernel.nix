# CachyOS kernel for the console. nixpkgs has no CachyOS kernel, so it comes
# from the nix-cachyos-kernel flake's `release` branch, which only carries
# kernels its Hydra has already built into the lantian binary cache.
{ flake, ... }:

{
  boot.kernelPackages =
    flake.inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest;

  # Takes effect only after the first activation that contains it; that first
  # switch passes the same two values with --option.
  nix.settings = {
    extra-substituters = [ "https://attic.xuyh0120.win/lantian" ];
    extra-trusted-public-keys = [ "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=" ];
  };
}
