{ ... }:

let
  chromeExtensionId = "aeblfdkhhhdcdjpifhhbdiojplfjncoa";
  firefoxExtensionId = "{d634138d-c276-4fc8-924b-40a0ea21d284}";
in
{
  programs._1password.enable = true;

  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "tristan" ];
  };

  # This NixOS module writes the same managed policy to Chromium and Chrome's
  # respective policy directories without touching either user profile.
  programs.chromium = {
    enable = true;
    extensions = [ chromeExtensionId ];
    extraOpts.PasswordManagerEnabled = false;
  };

  # Enabling this module owns the already-selected nixpkgs Firefox package and
  # its enterprise policy, avoiding a second Firefox installation.
  programs.firefox = {
    enable = true;
    policies = {
      OfferToSaveLogins = false;
      ExtensionSettings.${firefoxExtensionId} = {
        installation_mode = "force_installed";
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/1password-x-password-manager/latest.xpi";
      };
    };
  };

  # The inspected AppImage launches its browser process as zen-bin. The
  # browser extension itself remains a documented one-time manual install.
  environment.etc."1password/custom_allowed_browsers".text = ''
    zen-bin
  '';
}
