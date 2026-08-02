# Helix Abyss appearance

Helix Abyss is the workstation's repository-owned, near-black appearance policy.
It uses maintained Breeze components and adds colour rather than replacing the
desktop rendering stack. Deep backgrounds remain separated, text stays bright,
and a restrained blue accent provides focus without glow, blur, transparency,
animated wallpaper, or theme-store content.

The principal palette is `#080A0D` (deep background), `#0B0E12` (window),
`#10141A` (secondary), `#151A22` (raised), `#0D1117` (input), `#252C37`
(border), `#E6EAF0` and `#A9B1BD` (text), `#7396F5` (accent), and `#314E8A`
(selection). Positive, warning, negative, link, and visited-link colours are
`#7BC89C`, `#D9B66F`, `#E17B85`, `#8AB4FF`, and `#B49CFF`.

## Desktop integration

Plasma uses the `Helix Abyss` KDE colour scheme with Breeze Dark desktop style,
Breeze widget and decoration rendering, Breeze Dark icons, and the visible
Breeze cursor. The same local SVG is applied to Plasma desktops and the lock
screen. SDDM retains its packaged Breeze implementation but uses a dark loading
colour and that wallpaper. Plasma's panel, menus, tray, notifications, task
switcher, lock, and logout surfaces consequently inherit dark Breeze and the
custom scheme.

Qt 5 and Qt 6 continue through Plasma's native integration. GTK 3 and GTK 4 use
Breeze-Dark, Breeze Dark icons, `prefer-dark`, and dconf's desktop preference.
No global `GTK_THEME`, `QT_STYLE_OVERRIDE`, or `QT_QPA_PLATFORMTHEME` override is
set. This lets portals and native file pickers keep their normal integration.

The optional Hyprland session uses the same wallpaper through `swaybg`, blue and
subdued window borders, and repository-owned dark configurations for Waybar,
Mako, and Fuzzel. Existing bindings, workspaces, session management, and logout
behaviour are preserved.

Ghostty uses its packaged `Catppuccin Mocha` theme with no opacity or blur. VS
Code uses its verified built-in `Abyss` theme plus restrained workbench surface
overrides; terminal ANSI and syntax colours remain owned by that theme.

Chrome and Chromium receive a managed dark browser appearance plus official
Dark Reader extension ID `eimadpbcbfnmbkopoojfekhnkhdbieeh`. Firefox receives
locked dark chrome/content preferences and official Dark Reader add-on
`addon@darkreader.org`. Existing 1Password extension policy remains intact.
Dark Reader keeps its normal conservative defaults and can be toggled per site;
no force-inversion browser flag is used. Zen inherits the desktop dark preference,
but its immutable AppImage cannot reliably consume this Firefox enterprise
extension policy. Install official Dark Reader from Mozilla Add-ons once in Zen,
alongside the already documented 1Password extension.

Spotify and Plex are already dark. Haruna, Strawberry, VLC, ckb-next, and other
Qt applications inherit the desktop appearance. 1Password should follow the
system setting; confirm its in-app appearance after activation if it does not.
Obsidian's base theme is per vault: select **Settings → Appearance → Base color
scheme → Dark** once in each relevant vault. Helix does not scan for or modify
vault metadata and installs no community theme.

## Application and ownership

The `helix-abyss-theme` user service is installed system-wide but has
`ConditionUser=tristan`, explicit `HOME=/home/tristan`, and explicit
`XDG_CONFIG_HOME=/home/tristan/.config`. It runs once after a graphical session
starts and only repeats when the repository-owned content hash changes. It
updates individual KDE keys, merges only Helix-owned GTK keys, and structurally
merges theme keys into `~/.config/Code/User/settings.json`. Unrelated user values
are preserved. It does not run graphical applications.

Inspect or manually reapply it after activation with:

```bash
systemctl --user status helix-abyss-theme.service
journalctl --user -u helix-abyss-theme.service
rm ~/.config/helix/theme-revision
systemctl --user restart helix-abyss-theme.service
```

To temporarily return Plasma to ordinary Breeze Dark without deleting settings:

```bash
plasma-apply-colorscheme BreezeDark
plasma-apply-desktoptheme breeze-dark
```

The canonical assets are under `config/theme/`; `desktop/theme.nix` owns their
deployment and service. The service updates only selected keys in `kdeglobals`,
`kwinrc`, `plasmarc`, `kscreenlockerrc`, GTK 3/4 `settings.ini`, and VS Code user
settings. Appearance cannot safely be universal for every website or application,
so Zen, Obsidian vaults, and any application-specific preference remain documented
user choices.
