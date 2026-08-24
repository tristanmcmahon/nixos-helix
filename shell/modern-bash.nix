{ pkgs, ... }:

let
  # Pinned from tristanmcmahon/modern-bash commit
  # 55b1c4de6bc47e14285d55f6a1dfdf9fb494e806. Keeping the small runtime
  # snapshot in this repository makes NixOS builds independent of sibling
  # repository visibility and GitHub credentials.
  source = ../vendor/modern-bash;

  runtime = pkgs.stdenvNoCC.mkDerivation {
    pname = "modern-bash-runtime";
    version = "0.3.0-55b1c4d";
    src = source;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/modern-bash"
      cp -R bin docs scripts src "$out/share/modern-bash/"
      runHook postInstall
    '';
  };

  modern-bash = pkgs.writeShellApplication {
    name = "modern-bash";
    text = ''
      case ''${1:-} in
        install | uninstall)
          printf '%s\n' \
            'modern-bash is managed by the Helix NixOS configuration.' \
            'Edit shell/modern-bash.nix and rebuild the system instead.' >&2
          exit 2
          ;;
      esac
      exec ${runtime}/share/modern-bash/bin/modern-bash "$@"
    '';
  };
in
{
  environment.systemPackages = [ modern-bash ];

  # `init` prints only a quoted source statement. The sourced entrypoint is
  # interactive-only, idempotent, performs no downloads or installation, and
  # tolerates optional Git/terminfo support being absent.
  programs.bash.interactiveShellInit = ''
    eval "$(${modern-bash}/bin/modern-bash init)"
  '';
}
