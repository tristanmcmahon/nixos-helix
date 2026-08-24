{
  fetchFromGitHub,
  mame,
}:

# Keep the maintained NixOS 26.05 build recipe while locking the emulator to
# the version used by the authoritative NAS collection and its DAT files.
mame.overrideAttrs (_previousAttrs: {
  version = "0.275";

  src = fetchFromGitHub {
    owner = "mamedev";
    repo = "mame";
    rev = "mame0275";
    hash = "sha256-VD0T+zoR8fPZqRwTVrk2k5ui3tLQumEg1Fd64SJdszU=";
  };
})
