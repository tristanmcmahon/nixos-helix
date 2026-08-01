{ pkgs, ... }:

{
  # The attached original Corsair K70 RGB reports USB ID 1b1c:1b13. Use the
  # supported NixOS module so its daemon, package, and device rules have one
  # owner. The package currently needs its optional Qt DBus menu disabled to
  # avoid a missing dbusmenu-qt5 build dependency on the 25.11 channel.
  hardware.ckb-next = {
    enable = true;
    package = pkgs.ckb-next.overrideAttrs (old: {
      cmakeFlags = old.cmakeFlags ++ [ "-DUSE_DBUS_MENU=0" ];
    });
  };
}
