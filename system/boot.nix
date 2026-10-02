_:

{
  boot.supportedFilesystems = [ "cifs" ];

  boot.loader = {
    systemd-boot = {
      enable = true;
      # GC keeps 14 days of generations, but a busy fortnight can still fill
      # the ESP with kernels and initrds; cap the boot menu explicitly.
      configurationLimit = 20;
    };
    efi.canTouchEfiVariables = true;
    timeout = 5;
  };

  powerManagement.enable = true;
}
