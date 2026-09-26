{ pkgs, ... }:

let
  gitCredentialRepair = pkgs.writeShellApplication {
    name = "helix-git-credential-repair";
    runtimeInputs = with pkgs; [
      coreutils
      gh
      git
    ];
    text = ''
      target="$HOME/.gitconfig"
      xdg_target="$HOME/.config/git/config"

      remove_host_helpers() {
        local file=$1
        local host=$2
        local key="credential.https://$host.helper"

        [[ -f "$file" ]] || return 0
        git config --file "$file" --unset-all "$key" >/dev/null 2>&1 || true
      }

      for file in "$target" "$xdg_target"; do
        remove_host_helpers "$file" github.com
        remove_host_helpers "$file" gist.github.com
      done

      touch "$target"
      chmod 600 "$target"

      for host in github.com gist.github.com; do
        key="credential.https://$host.helper"

        # The empty helper resets lower-precedence helpers. Keep the actual
        # command PATH-based so a Nix store garbage collection cannot strand
        # Git on an obsolete /nix/store/.../gh path.
        git config --file "$target" --add "$key" ""
        git config --file "$target" --add "$key" '!gh auth git-credential'
      done

      printf '%s\n' 'GitHub credential helper: !gh auth git-credential'
    '';
  };
in
{
  environment.systemPackages = [ gitCredentialRepair ];

  systemd.user.services.helix-git-credential-helper = {
    description = "Keep GitHub Git credentials independent of Nix store paths";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = "tristan";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${gitCredentialRepair}/bin/helix-git-credential-repair";
    };
  };
}
