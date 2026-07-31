{ ... }:

{
  # PLACEHOLDER: these match the supplied Pacific/Auckland environment and a
  # New Zealand English workstation. Change them if Helix will live elsewhere.
  time.timeZone = "Pacific/Auckland";
  i18n.defaultLocale = "en_NZ.UTF-8";

  # The console keymap also supplies the initial XKB choice used by GNOME. User
  # layouts added in GNOME are stored per-user rather than in this base policy.
  console.keyMap = "us";
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
}
