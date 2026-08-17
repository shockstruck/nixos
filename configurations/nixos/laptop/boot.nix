{
  boot.initrd.systemd = {
    enable = true;
    tpm2.enable = true;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
