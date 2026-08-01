{ pkgs, ... }:

let
  # Source: https://github.com/tristanmcmahon/modern-bash
  # Commit: 55b1c4de6bc47e14285d55f6a1dfdf9fb494e806 (2026-08-01 integration)
  # The upstream runtime is packaged intact. Its installer is available as an
  # explicit command but is never run by activation or interactive startup.
  source = pkgs.fetchFromGitHub {
    owner = "tristanmcmahon";
    repo = "modern-bash";
    rev = "55b1c4de6bc47e14285d55f6a1dfdf9fb494e806";
    hash = "sha256-7H4SkRupATaGTqkACfCqdCLKaNDsd488+hxVmQ//IUY=";
  };

  modern-bash = pkgs.stdenvNoCC.mkDerivation {
    pname = "modern-bash";
    version = "0.3.0-55b1c4d";
    inherit source;
    src = source;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin" "$out/share/modern-bash"
      cp -R bin docs scripts src "$out/share/modern-bash/"
      ln -s ../share/modern-bash/bin/modern-bash "$out/bin/modern-bash"
      runHook postInstall
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
