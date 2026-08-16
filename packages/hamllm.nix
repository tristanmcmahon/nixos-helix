{
  pkgs ? import <nixpkgs> { },
}:

with pkgs;

let
  rev = "80b3a8deed116eca6f46e202b52f99b734392cae";
  sha = "18a0siviljm9kn6yp34scdw4wn22mpwys2f8j86glv83m2gyr19f";
in

buildPythonPackage rec {
  pname = "hamllm";
  version = "0.0.1";
  src = fetchFromGitHub {
    owner = "tristanmcmahon";
    repo = "hamLLM";
    rev = rev;
    sha256 = sha;
  };
  propagatedBuildInputs = [
    python310Packages.requests
    python310Packages.google-api-python-client
    python310Packages.google-auth
  ];
  doCheck = false;
}
