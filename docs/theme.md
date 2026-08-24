# Graphite + Fern appearance

Graphite + Fern is Helix's repository-owned dark appearance policy: layered
graphite surfaces, restrained fern-green interaction states, readable neutral
text, and distinct amber/red warning states. It uses maintained Breeze
components rather than a theme-store stack, excessive transparency, or a new
theme engine.

The canonical palette is `config/theme/palette.nix`: `#0B0D0C` deep canvas,
`#181C19` primary surface, `#232824` raised surface, `#303832` hover surface,
`#3A443C` border,
`#E4E8E5` primary text, `#AEB8B1` secondary text, `#7E8981` muted text,
`#67B87A` primary green, `#81C995` active green, `#3E7650` deep green,
`#315E3E` accessible selection green, `#D6AD63` warning, and `#D77A78` error.

## Desktop integration

Plasma, Qt applications, Dolphin, settings, dialogs, panel surfaces, launcher,
tray, notifications, and task states use the `Helix Graphite Fern` KDE colour
scheme with Breeze Dark rendering. Breeze also remains the icon, cursor, widget,
and KWin decoration family. Active windows gain a restrained green blend/focus
cue, inactive windows recede, and Breeze uses a small border with conservative
outline and shadow settings. The existing Plasma panel layout remains mutable
and is not rearranged.

The local scalable SVG anchors Plasma, the lock screen, SDDM, and Hyprland.
SDDM remains packaged Breeze with the Graphite + Fern wallpaper and loading
colour. GTK 3/4 use maintained Breeze-Dark, Breeze Dark icons, and the native
dark preference; no global GTK or Qt environment override is set.

Ghostty has four repository-owned profiles: Main, Moss, Slate, and
Ember. In Plasma, launch **Ghostty Profile** or press
`Meta+Shift+Return` to switch the default font and palette live. Every new
Ghostty surface after the first one—including a split, tab, or window—opens the
same compact colour chooser before Bash starts. This runs inside the new PTY,
so it works in Plasma and the optional Hyprland session without compositor
window/PID timing hooks. Cancelling the chooser simply keeps the current
default. A matching Konsole colour scheme/profile is installed and selected
when the applicator runs in Plasma. VS Code uses built-in Default Dark Modern
syntax colours with owned workbench surface, selection, focus, and status
colours. Browser chrome uses the graphite base where policy supports it. Dark
Reader remains available without fragile per-site CSS.

The optional Hyprland session shares the wallpaper and palette through its
existing Waybar, Mako, and Fuzzel files. Its workspaces and normal session
behaviour are unchanged; the Ghostty surface chooser is now shared with Plasma.
Obsidian remains per-vault: select its Dark base colour scheme when necessary.
Zen follows the system preference but retains its own profile-local extension
state.

Steam does not inherit KDE colours. NixOS therefore installs the maintained
AdwSteamGtk wrapper and a repository-owned Graphite + Fern custom-colour file.
Applying it remains an explicit runtime operation because the upstream tool
patches mutable Steam client files, requires a network connection to retrieve
the skin, and may need to be rerun after a Steam update. Close Steam completely,
then run:

```bash
helix-apply-steam-theme
```

The helper refuses to run while Steam is open, selects the upstream OLED base,
disables rounded elements, uses conventional window controls, and enables the
repository-owned colour override. Launch AdwSteamGtk from Plasma to change or
uninstall the skin. Store, Community, and profile web pages remain controlled by
Steam and cannot be recoloured by this mechanism.

## Ownership and mutable state

`desktop/theme.nix` owns packaging, SDDM, deployment, and the revision-idempotent
`helix-graphite-fern-theme` user service. It updates selected KDE keys, merges
only repository-owned GTK keys, and structurally merges theme keys into VS Code
without discarding unrelated settings. `desktop/ghostty.nix` deploys Ghostty;
`desktop/fonts.nix` remains the sole font owner.

Plasma panel geometry, widget order, desktop icon layout, per-monitor geometry,
and application-specific settings remain mutable user state. This preserves the
working layout and avoids introducing Home Manager or plasma-manager for visual
settings the current architecture already handles cleanly.

Inspect or force the current revision with:

```bash
systemctl --user status helix-graphite-fern-theme.service
journalctl --user -u helix-graphite-fern-theme.service
helix-apply-theme --force
```

To preview without selecting a persistent boot generation, run
`./scripts/rebuild.sh test`, then `helix-apply-theme --force`. Apply persistently
with `./scripts/rebuild.sh switch` and log out/in if shell components have not
reloaded. Roll back the system generation with
`sudo nixos-rebuild switch --rollback`; ordinary Breeze Dark can be selected
temporarily with `plasma-apply-colorscheme BreezeDark` and
`plasma-apply-desktoptheme breeze-dark`.
