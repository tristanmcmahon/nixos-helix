_:

{
  boot.supportedFilesystems = [ "cifs" ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    timeout = 5;
  };

  powerManagement.enable = true;
}
