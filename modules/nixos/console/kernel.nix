# CachyOS kernel for the console. nixpkgs has no CachyOS kernel, so it comes
# from the nix-cachyos-kernel flake's `release` branch, which only carries
# kernels its Hydra has already built into upstream's `cache.lantian.pub`
# binary cache; `cache.xinux.uz` is kept as a separately built second source.
{ flake, ... }:

{
  boot.kernelPackages =
    flake.inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest;

  # Takes effect only after the first activation that contains it; that first
  # switch passes the same values with --option.
  nix.settings = {
    extra-substituters = [
      "https://cache.lantian.pub/lantian"
      "https://cache.xinux.uz"
    ];
    extra-trusted-public-keys = [
      "lantian:WVGO7vsRMSEN+h7Lp7kv6SAmrkEXgUGbbXm7jMDjBuQ="
      "cache.xinux.uz:BXCrtqejFjWzWEB9YuGB7X2MV4ttBur1N8BkwQRdH+0="
    ];
  };
}
