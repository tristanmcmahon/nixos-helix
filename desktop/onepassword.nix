_:

let
  helix = import ../config/helix.nix;
in
{
  programs._1password.enable = true;

  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ helix.user ];
  };
}
