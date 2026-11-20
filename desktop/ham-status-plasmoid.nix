{ pkgs, ... }:

let
  # The package source is repo-owned; Plasma discovers it from the system
  # profile. No kpackagetool6 or user-local installation is needed on rebuild.
  hamStatus = pkgs.runCommand "alienrobot-service-health-plasmoid" { } ''
    destination=$out/share/plasma/plasmoids/org.alienrobot.hamstatus
    mkdir -p "$destination"
    cp -R ${../plasmoids/org.alienrobot.hamstatus}/contents "$destination/"
    cp ${../plasmoids/org.alienrobot.hamstatus}/metadata.json "$destination/"
  '';
in
{
  environment.systemPackages = [ hamStatus ];
}
