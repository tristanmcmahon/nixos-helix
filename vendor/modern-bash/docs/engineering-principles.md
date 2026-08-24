# Engineering principles

Modern Bash should feel unsurprising under pressure. These principles are the
constraints for new code, not aspirations to apply later.

## Preserve Unix composition

Pipeline data belongs on standard output. Human-oriented status, progress, and
diagnostics belong on standard error unless a command's explicit product is a
human-readable report. Output helpers use `printf`, never `echo`, and never
interpret user-provided text as a format string.

Exit statuses are part of the interface. A missing optional enhancement, a
redirected stream, or a plain terminal is not an error. Usage errors return 64;
failed required checks return non-zero.

## Detect capabilities, do not guess intent

Capabilities are detected for the actual output file descriptor because stdout
and stderr can be redirected independently. Automatic styling requires a TTY,
a usable `TERM`, and no applicable opt-out. Detection is safe when terminfo is
missing or broken and always has a plain-text fallback.

Explicit project settings take precedence over conventional environment
settings, followed by automatic detection. `NO_COLOR` is presence-based,
including an empty value. Tests cover every override so precedence cannot drift
accidentally.

## Theme by meaning

Callers ask for information, success, warning, error, or debug output. They do
not choose raw colour codes. The theme maps those meanings to ANSI, 256-colour,
24-bit, Unicode, or ASCII representations. No-colour mode emits no escape
sequence at all, including resets.

Colour is never the only carrier of meaning: every status has a textual or
symbolic label, and plain output remains readable.

## Be a polite sourced library

Sourcing Modern Bash must not change shell options, traps, aliases, `IFS`, or
the working directory. Public functions and globals use the `modern_bash::` and
`MODERN_BASH_` namespaces. Commands that need temporary configuration run in a
subshell so they do not leak state back to a caller.

Inputs are quoted, external commands are optional where practical, and failure
paths remain correct with `nounset` and `pipefail`. Libraries do not enable
`errexit` on behalf of applications.

The interactive entrypoint checks `$-` before loading libraries or user
configuration. Non-interactive sourcing is silent and inert, while repeated
interactive initialization is idempotent.

Module loading is fail-closed: a partial or corrupt runtime never marks itself
loaded. Internal guard variables inherited through the environment are hints,
not proof that the corresponding functions exist.

## Treat prompt data as untrusted

Working directories and version-control references can contain shell syntax.
Dynamic prompt data must remain behind static parameter references in `PS1`,
must not be interpolated as prompt source, and must have terminal control bytes
removed. ANSI spans use Readline's non-printing markers so cursor calculations
remain correct.

Prompt hooks preserve the previous command status and compose with an existing
`PROMPT_COMMAND` without duplicate installation. Capability probing for the
prompt must not alter a previously configured output stream's theme snapshot.
Status restoration must not manufacture extra `ERR` traps. Activation is
reversible, and shutdown restores exact unset, scalar, or indexed-array state
when Modern Bash still owns the hook.

User configuration is trusted Bash, explicitly analogous to `.bashrc`. Path
resolution follows the XDG base-directory convention, missing configuration is
normal, and invalid settings fail visibly before any feature is enabled.

## Prefer a small compatibility surface

Bash 3.2 is the supported floor, including the system Bash supplied by macOS.
Newer Bash features may be used only behind a compatible fallback or alongside
an explicit compatibility change. Runtime code depends on Bash and ubiquitous
Unix tools; terminal helpers such as `tput` are opportunistic.

The managed installer may copy runtime files and documentation, but it never
edits shell startup files or user configuration. It must refuse unmanaged
collisions, follow its own launcher symlink safely, and preserve configuration
during uninstall.

## Make behaviour executable

Every public behaviour needs a deterministic test, especially stream routing,
format-string safety, override precedence, and escape-sequence suppression.
Tests must not depend on the terminal running them. The test harness itself has
no third-party runtime dependency, and every shell file is checked with
ShellCheck. Continuous integration exercises Ubuntu's Bash and the macOS system
Bash 3.2 so the compatibility claim remains executable.
