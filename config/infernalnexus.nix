{
  host = "192.168.1.8";
  credentialsFile = "/etc/nixos/secrets/infernalnexus-smb";
  user = "tristan";
  group = "users";
  smbVersion = "2.0";
  security = "ntlmssp";
  mountTimeout = "15s";
  idleTimeout = "10min";

  shares = {
    nas1 = {
      source = "//192.168.1.8/nas1";
      mountPoint = "/mnt/infernalnexus/nas1";
    };
    roms = {
      source = "//192.168.1.8/roms";
      mountPoint = "/mnt/infernalnexus/roms";
    };
  };
}
