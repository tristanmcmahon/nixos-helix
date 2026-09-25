_:

let
  infernalnexus = import ../config/infernalnexus.nix;
in
{
  networking.hosts = {
    "192.168.1.2" = [ "mister" ];
    "${infernalnexus.host}" = [ "infernalnexus" ];
  };
}
