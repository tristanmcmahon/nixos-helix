# 1Password

The dedicated NixOS modules install the native 1Password desktop application,
the `op` CLI, browser-support wrapper, `onepassword` groups, and Polkit policy
for `tristan`. Plasma already supplies its authentication agent, so no duplicate
agent is installed. Quick Access and tray support come from the normal desktop
package. Updates arrive through the selected NixOS package channel.

## Browser integration

- Google Chrome and Chromium receive the official extension ID
  `aeblfdkhhhdcdjpifhhbdiojplfjncoa` through managed Chromium policy. The same
  policy disables new offers from their built-in password manager.
- Firefox is owned once by `programs.firefox` and receives the official AMO
  extension `{d634138d-c276-4fc8-924b-40a0ea21d284}` through
  `ExtensionSettings`. Enterprise policy disables new built-in password-save
  prompts.
- Zen Browser's inspected AppImage process is `zen-bin`, which is declared in
  `/etc/1password/custom_allowed_browsers`. Although Zen contains Firefox's
  policy engine, its AppImage application tree is immutable and does not offer
  a reliable system policy location in this package. Install the official
  1Password Firefox extension once from Mozilla Add-ons in Zen.

These policies neither edit profiles nor erase existing saved passwords. Before
manually removing old browser passwords later, use each browser's password
manager export function and protect the exported plaintext file carefully.

After signing in, enable **Settings → Browser → Connect with 1Password in the
browser** in the desktop app and **Integrate this extension with the 1Password
desktop app** in each extension. This enables shared locking and unlocking where
the browser supports it. Enable system authentication in the desktop settings
if desired.

For CLI integration, enable **Settings → Developer → Integrate with 1Password
CLI**. After activation, `op --version` works without tokens or automatic sign-in;
the unlocked desktop app can authorize later CLI use.

## Optional SSH agent

No system-wide SSH agent is selected automatically. That preserves normal
file-based key fallback if 1Password is locked or closed and avoids overwriting
`~/.ssh/config`. To opt in, enable **1Password → Settings → Developer → Use the
SSH agent**, then add this user-controlled line beneath an appropriate `Host`
section in `~/.ssh/config`:

```sshconfig
IdentityAgent ~/.1password/agent.sock
```

The path is the documented Linux socket. Existing key files remain available;
Git signing through 1Password is a separate future option.

Local application state remains under the user's normal 1Password data directory
(`~/.config/1Password`). No account email, Secret Key, vault content, token, or
other account data is stored in Git or the Nix store.
