{ lib, ... }:

{
  # PipeWire and PulseAudio cannot both own the audio devices. This disables
  # the legacy daemon; the compatibility protocol below still supports normal
  # PulseAudio applications.
  services.pulseaudio.enable = false;

  # PipeWire is the audio graph used by modern GNOME. The PulseAudio protocol
  # server is a compatibility interface implemented by PipeWire, not a second
  # competing audio daemon.
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;

    # 32-bit audio libraries are primarily needed by legacy games and Wine;
    # neither is part of this workstation, so they are deliberately omitted.
    alsa.support32Bit = lib.mkDefault false;
  };

  # PipeWire uses realtime scheduling for reliable low-latency playback and
  # capture without granting broad realtime privileges to desktop processes.
  security.rtkit.enable = true;

  # Device-specific codec quirks, USB audio devices, and microphone identities
  # must come from the inventory. ALSA and PipeWire discover ordinary devices
  # without hard-coded card numbers, which are not stable identifiers.
}
