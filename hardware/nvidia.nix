{ ... }:

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

    # No package override is used: Nixpkgs selects a stable driver compatible
    # with the selected kernel.

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
