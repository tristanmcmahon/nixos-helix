{ pkgs, ... }:

{
  # These clients inspect hardware; none enables a monitoring or server daemon.
  environment.systemPackages = with pkgs; [
    pciutils
    usbutils
    lm_sensors
    smartmontools
    evtest
    # Helix has an NVIDIA GPU; the vendor-specific build avoids pulling AMD,
    # Intel, and other GPU backends into the workstation closure.
    nvtopPackages.nvidia

    # Retained from the working configuration for storage, network, camera,
    # OpenGL, and Vulkan diagnosis.
    nvme-cli
    inxi
    ethtool
    iw
    v4l-utils
    mesa-demos
    vulkan-tools
  ];
}
