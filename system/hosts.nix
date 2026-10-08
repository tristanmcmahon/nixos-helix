_:

let
  infernalnexus = import ../config/infernalnexus.nix;
in
{
  networking.hosts = {
    "192.168.1.2" = [ "mister" ];
    "${infernalnexus.host}" = [ "infernalnexus" ];
  };

  # Synology DSM's sshd offers no post-quantum key exchange and cannot be
  # upgraded from here; silence OpenSSH's warning for the NAS only, so any
  # other host lacking PQ key exchange still warns.
  programs.ssh.extraConfig = ''
    Host infernalnexus ${infernalnexus.host}
      WarnWeakCrypto no-pq-kex
  '';
}
