# The single source for Helix appearance. desktop/theme.nix derives the theme
# list, helix-theme's choices and the random pool from `order` and `themes`;
# scripts/generate-theme-family.py renders config/theme/templates from them.
{
  # Neutral colours shared by every theme; SDDM and browser chrome use them.
  base = {
    background = "#0B0D0C";
    text = "#E4E8E5";
    textSecondary = "#AEB8B1";
    textMuted = "#7E8981";
    warning = "#D6AD63";
    error = "#D77A78";
  };

  order = [
    "fern"
    "petrol"
    "plum"
    "oxide"
    "amber"
    "rosewood"
    "hotdog"
  ];

  # Roles: accent (primary), accentBright, accentDeep, selection, then the four
  # surface steps from window background to border.
  themes = {
    fern = {
      name = "Fern";
      description = "graphite with restrained fern green (default)";
      random = true;
      accent = "#67B87A";
      accentBright = "#81C995";
      accentDeep = "#3E7650";
      selection = "#315E3E";
      surface = "#181C19";
      surfaceRaised = "#232824";
      surfaceHover = "#303832";
      border = "#3A443C";
    };
    petrol = {
      name = "Petrol";
      description = "muted deep petrol and teal";
      random = true;
      accent = "#5FA8A3";
      accentBright = "#79C2BC";
      accentDeep = "#386D69";
      selection = "#2D5754";
      surface = "#171D1C";
      surfaceRaised = "#222B29";
      surfaceHover = "#2E3937";
      border = "#394846";
    };
    plum = {
      name = "Plum";
      description = "dusty aubergine and plum";
      random = true;
      accent = "#A47AB8";
      accentBright = "#C096D0";
      accentDeep = "#654A73";
      selection = "#50395B";
      surface = "#1C181E";
      surfaceRaised = "#29232C";
      surfaceHover = "#37303A";
      border = "#473C4B";
    };
    oxide = {
      name = "Oxide";
      description = "muted rust and copper";
      random = true;
      accent = "#BE7A55";
      accentBright = "#D69772";
      accentDeep = "#794C35";
      selection = "#603B2B";
      surface = "#1D1917";
      surfaceRaised = "#2B2521";
      surfaceHover = "#39312C";
      border = "#4A4039";
    };
    amber = {
      name = "Amber";
      description = "desaturated ochre and gold";
      random = true;
      accent = "#C3A35D";
      accentBright = "#D8BC7A";
      accentDeep = "#786537";
      selection = "#5D4E2C";
      surface = "#1D1B16";
      surfaceRaised = "#2A2720";
      surfaceHover = "#38342A";
      border = "#494435";
    };
    rosewood = {
      name = "Rosewood";
      description = "dark wine and rosewood";
      random = true;
      accent = "#B66E7D";
      accentBright = "#CF8997";
      accentDeep = "#734550";
      selection = "#59363E";
      surface = "#1D1719";
      surfaceRaised = "#2B2225";
      surfaceHover = "#392D31";
      border = "#493A3F";
    };
    hotdog = {
      name = "Hot Dog Stand";
      description = "regrettably available.";
      random = false;
      accent = "#FF0000";
      accentBright = "#FFFFFF";
      accentDeep = "#C00000";
      selection = "#FF0000";
      surface = "#FFFF00";
      surfaceRaised = "#FF0000";
      surfaceHover = "#000000";
      border = "#FFFFFF";
    };
  };
}
