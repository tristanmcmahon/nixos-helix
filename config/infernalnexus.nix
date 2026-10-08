let
  host = "192.168.1.8";
  nas1 = "/mnt/infernalnexus/nas1";
  # hamology keeps Infernalnexus's service-state archives in
  # /volume1/nas1/data/backups; over the nas1 share that is this directory.
  # Every Helix backup lives beside them, each in its own subdirectory, so
  # hamology's retention (which only touches hamology-state-* archives) and
  # Helix's never meet.
  backupRoot = "${nas1}/data/backups";
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

  backups = {
    root = backupRoot;
    # Nightly backups keep the two newest copies, Helix's and hamology's alike.
    keep = 2;
    restic = "${backupRoot}/helix-restic";
    reinstall = "${backupRoot}/helix-reinstall";
  };

  shares = {
    nas1 = {
      source = "//${host}/nas1";
      mountPoint = nas1;
    };
    roms = {
      source = "//${host}/roms";
      mountPoint = "/mnt/infernalnexus/roms";
    };
  };
}
