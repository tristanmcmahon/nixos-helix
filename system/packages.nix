{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # Editing, retrieval, and structured text inspection.
    git
    helix
    curl
    wget
    jq
    ripgrep
    fd
    tree
    file

    # Hardware identification and health tools. These are diagnostics only;
    # installing their clients does not enable a monitoring or server daemon.
    pciutils
    usbutils
    smartmontools
    nvme-cli
    lm_sensors
    inxi
    ethtool
    iw
    v4l-utils

    # `glxinfo` and `vulkaninfo` make software-rendering mistakes visible during
    # initial GPU validation. They do not add a gaming or CUDA stack.
    mesa-demos
    vulkan-tools
  ];

  # Packages intentionally absent include language ecosystems, containers,
  # virtualisation, CUDA, Wine, Steam, and other gaming software. Add software
  # here only when Helix has a present requirement for it.
}
