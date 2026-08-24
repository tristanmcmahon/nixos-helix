let
  user = "tristan";
  home = "/home/${user}";
in
{
  inherit user home;
  displayName = "Tristan";
  userGroup = "users";
  projectsRoot = "${home}/Projects";
}
