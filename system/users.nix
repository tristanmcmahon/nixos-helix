{ ... }:

{
  users.users.tristan = {
    isNormalUser = true;
    description = "Tristan";

    # wheel permits authenticated sudo; networkmanager permits changing wired
    # and wireless connections from GNOME Settings.
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
  };

  # NixOS keeps account passwords mutable by default. No password, hash, or SSH
  # key belongs in this repository: set the account password locally with
  # `sudo passwd tristan` before relying on this account for login.
  users.mutableUsers = true;

  # Retain the normal password prompt for administrative actions. Membership in
  # wheel is not intended to become passwordless privilege escalation.
  security.sudo.wheelNeedsPassword = true;
}
