let
  host = "192.168.1.8";
in
{
  inherit host;
  credentialsFile = "/etc/nixos/secrets/infernalnexus-smb";
  user = "tristan";
  group = "users";
  smbVersion = "2.0";
  security = "ntlmssp";
  mountTimeout = "15s";
  idleTimeout = "10min";

  shares = {
    nas1 = {
      source = "//${host}/nas1";
      mountPoint = "/mnt/infernalnexus/nas1";
    };
    roms = {
      source = "//${host}/roms";
      mountPoint = "/mnt/infernalnexus/roms";
    };
  };
}
