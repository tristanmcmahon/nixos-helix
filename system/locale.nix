_:

{
  # Helix uses New Zealand time and locale settings.
  time.timeZone = "Pacific/Auckland";
  i18n.defaultLocale = "en_NZ.UTF-8";

  # The console keymap also supplies the initial XKB choice used by Plasma. User
  # layouts added in System Settings are stored per-user rather than here.
  console.keyMap = "us";
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
}
