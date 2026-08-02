{ ... }:

let
  chromeExtensionId = "aeblfdkhhhdcdjpifhhbdiojplfjncoa";
  chromeDarkReaderId = "eimadpbcbfnmbkopoojfekhnkhdbieeh";
  firefoxExtensionId = "{d634138d-c276-4fc8-924b-40a0ea21d284}";
  firefoxDarkReaderId = "addon@darkreader.org";
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
    extensions = [
      chromeExtensionId
      chromeDarkReaderId
    ];
    extraOpts = {
      BrowserThemeColor = "#080A0D";
      PasswordManagerEnabled = false;
    };
  };

  # Enabling this module owns the already-selected nixpkgs Firefox package and
  # its enterprise policy, avoiding a second Firefox installation.
  programs.firefox = {
    enable = true;
    preferences = {
      "browser.theme.content-theme" = 0;
      "browser.theme.toolbar-theme" = 0;
      "layout.css.prefers-color-scheme.content-override" = 0;
      "ui.systemUsesDarkTheme" = 1;
    };
    policies = {
      OfferToSaveLogins = false;
      ExtensionSettings = {
        ${firefoxExtensionId} = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/1password-x-password-manager/latest.xpi";
        };
        ${firefoxDarkReaderId} = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
        };
      };
    };
  };

  # The inspected AppImage launches its browser process as zen-bin. The
  # browser extension itself remains a documented one-time manual install.
  environment.etc."1password/custom_allowed_browsers".text = ''
    zen-bin
  '';
}
