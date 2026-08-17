{ lib, ... }:

{
  disko.devices.disk.main = {
    type = "disk";
    device = lib.mkDefault "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        root = {
          label = "cryptroot";
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            extraFormatArgs = [ "--type" "luks2" ];
            settings = {
              allowDiscards = true;
              crypttabExtraOpts = [ "tpm2-device=auto" ];
            };
            content = {
              type = "btrfs";
              subvolumes = {
                "/root" = {
                  mountpoint = "/";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "/home" = {
                  mountpoint = "/home";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
              };
            };
          };
        };
      };
    };
  };
}
