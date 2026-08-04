_:

let
  chrome1PasswordId = "aeblfdkhhhdcdjpifhhbdiojplfjncoa";
  chromeDarkReaderId = "eimadpbcbfnmbkopoojfekhnkhdbieeh";
  firefox1PasswordId = "{d634138d-c276-4fc8-924b-40a0ea21d284}";
  firefoxDarkReaderId = "addon@darkreader.org";
in
{
  # Chromium and Chrome consume the same managed policy without modifying
  # either browser's user profile.
  programs.chromium = {
    enable = true;
    extensions = [
      chrome1PasswordId
      chromeDarkReaderId
    ];
    extraOpts = {
      BrowserThemeColor = "#030405";
      PasswordManagerEnabled = false;
    };
  };

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
        ${firefox1PasswordId} = {
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
}
