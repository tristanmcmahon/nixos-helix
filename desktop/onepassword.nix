{ ... }:

{
  programs._1password.enable = true;

  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "tristan" ];
  };

  # The inspected AppImage launches its browser process as zen-bin. The
  # browser extension itself remains a documented one-time manual install.
  environment.etc."1password/custom_allowed_browsers".text = ''
    zen-bin
  '';
}
