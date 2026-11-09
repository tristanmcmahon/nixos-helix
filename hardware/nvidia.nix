{ config, ... }:

{
  # The RTX 5080 is a Blackwell GPU. NVIDIA lists this PCI family as requiring
  # its open kernel modules; `open = true` selects those modules while the
  # matching proprietary user-space OpenGL/Vulkan libraries remain in use.
  services.xserver.videoDrivers = [ "nvidia" ];

  # This enables the standard NixOS graphics stack and exposes the vendor GL,
  # EGL and Vulkan drivers to both Wayland and Xwayland applications.
  hardware.graphics.enable = true;

  hardware.nvidia = {
    # Plasma's Wayland compositor needs DRM kernel modesetting. Current NixOS
    # also derives the NVIDIA DRM framebuffer parameter from this setting.
    modesetting.enable = true;

    open = true;

    # 620.70.06 is intentionally pinned ahead of this repo's Nixpkgs default
    # (595.71.05). It was qualified on this RTX 5080 on 2026-11-09 after the
    # previous driver repeatedly hit NVIDIA Xid 109 / CTX SWITCH TIMEOUT under
    # sustained Proton workloads. These are the exact artifacts used by the
    # isolated qualification generation; do not replace them with moving
    # branch aliases. Re-evaluate this override on every Nixpkgs bump until
    # Nixpkgs' packaged stable driver is >= 620.70.06 and has been requalified.
    package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
      version = "620.70.06";
      sha256_64bit = "1cflmw275gpwpkjs4qh3my8980wd4dv9qgfapicpbh08plx8w499";
      openSha256 = "sha256-dV8vzniUl3UJoG2Q3KdoUJigLRuQeTniUfB670gb1Mw=";
      settingsSha256 = "17x1plnn9p5w4cidibr1zga77a4md301qr8lwhgy1xa9f6cm2l08";
      persistencedSha256 = "144jq28bw3fjsl5sipwgy4gfyxhjrly2h9fz29kivggb1a2b748n";
    };

    # Preserve video memory across suspend. On current stable drivers NixOS
    # uses NVIDIA's kernel suspend notifier when available, otherwise it
    # installs the driver's systemd suspend/resume units.
    powerManagement.enable = true;

    # This is the one vendor-specific graphical diagnostic retained. It is not
    # required for Plasma display layout, which remains managed by System Settings.
    nvidiaSettings = true;
  };

  # PRIME is intentionally absent. It requires real PCI bus IDs and knowledge
  # of whether Helix has an active iGPU; inventing those values could prevent
  # the display manager from starting. Plasma's KWin discovers outputs
  # dynamically, so connector names and EDIDs also do not belong here.
}
