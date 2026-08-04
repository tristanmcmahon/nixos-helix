{ ... }:

{
  services.openssh = {
    enable = true;
    openFirewall = true;

    settings = {
      PermitRootLogin = "no";
      PubkeyAuthentication = true;
      # Keep both bootstrap methods available until hamkeydist has installed and
      # verified reverse-login public keys from mister and infernalnexus.
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = true;
    };
  };
}
