# Configuration

Modern Bash works without a configuration file. The default feature set is the
prompt, with Git detection enabled, non-zero exit statuses shown, and a
two-line layout.

## Activation

Add this to `.bashrc` when the `modern-bash` executable is on `PATH`:

```bash
eval "$(modern-bash init)"
```

`modern-bash init` only prints a safely quoted source statement. The sourced
entrypoint checks for an interactive shell before loading any other file, and
repeated activation in the same shell is a no-op.

The managed installer does not edit `.bashrc`. When using the default prefix,
ensure `$HOME/.local/bin` is on `PATH` before the activation line.

## Path resolution

The first applicable location wins:

1. `MODERN_BASH_CONFIG_FILE`, including an empty value to disable loading;
2. `$XDG_CONFIG_HOME/modern-bash/config.bash` when `XDG_CONFIG_HOME` is an
   absolute path;
3. `$HOME/.config/modern-bash/config.bash`.

A missing file is normal and activates built-in defaults. A path that exists
but is not a readable regular file is an initialization error.

The file is sourced as trusted Bash in the interactive shell. This makes
configuration flexible, but it should be protected with the same care as
`.bashrc`.

## Features

`MODERN_BASH_FEATURES` is a comma-separated list with no whitespace. The only
current feature is `prompt`:

```bash
MODERN_BASH_FEATURES=prompt
```

Disable all feature modules while retaining the bootstrap and libraries:

```bash
MODERN_BASH_FEATURES=
```

Unknown names and empty entries such as `prompt,,other` are rejected rather
than silently ignored.

## Capabilities and output

Colour detection uses the first applicable control:

1. `MODERN_BASH_COLOR=always|never|auto`;
2. the presence of `FORCE_COLOR` (`0` disables colour, `2` and `3` select the
   richer ANSI capability levels, and any other value—including empty—selects
   base ANSI colour);
3. the presence of `NO_COLOR`, including an empty value;
4. automatic output-terminal and terminfo detection.

`MODERN_BASH_UNICODE=always|never|auto` and
`MODERN_BASH_HYPERLINKS=always|never|auto` independently override Unicode and
terminal-hyperlink detection. Invalid `MODERN_BASH_*` capability values are
configuration errors.

Set `MODERN_BASH_DEBUG=1` (also accepting `true`, `yes`, or `on`, without
regard to case) to enable messages sent through
`modern_bash::output::debug`. Debug output is disabled by default.

## Prompt

The prompt contains the previous command's failure status, an abbreviated
working directory, an optional Git branch or detached commit, and a prompt
symbol. It automatically follows terminal colour and Unicode capabilities.

Available settings:

| Variable | Values | Default | Meaning |
| --- | --- | --- | --- |
| `MODERN_BASH_PROMPT_GIT` | `0`, `1` | `1` | Show Git context when available |
| `MODERN_BASH_PROMPT_STATUS` | `always`, `nonzero`, `never` | `nonzero` | Choose when exit status is shown |
| `MODERN_BASH_PROMPT_MULTILINE` | `0`, `1` | `1` | Select one-line or two-line layout |

Modern Bash composes idempotently around an existing `PROMPT_COMMAND`, capturing
status before it and rendering the Modern Bash prompt afterward. Scalar hooks,
indexed command arrays, comments, and trailing separators are supported. It
saves the original `PS1` in `MODERN_BASH_PROMPT_ORIGINAL_PS1` for inspection.

Restore the original prompt and hook state in the current shell with:

```bash
modern_bash::bootstrap::shutdown
```

Shutdown is idempotent and preserves a `PS1` installed by another tool after
Modern Bash. If `PROMPT_COMMAND` changed after activation, shutdown refuses to
overwrite it and reports an actionable error. Open a new shell to reload a
changed config file.

The standard Bash `promptvars` shell option must remain enabled. Modern Bash
reports an initialization error instead of silently changing that option.

Paths and branch names remain behind static variable references in `PS1` and
terminal control characters are replaced. This prevents dynamic repository or
directory names from becoming executable prompt substitutions.

## Diagnose configuration

Run:

```bash
modern-bash doctor
```

The doctor verifies the interactive entrypoint, resolves and loads the
effective config in its isolated process, validates settings and feature names,
and reports optional Git availability. It labels the prompt as *configured*,
which does not imply activation in the parent shell. A missing config or Git
executable is not a failure.

`--plain` controls only report presentation. It suppresses ANSI and Unicode
labels while continuing to report the terminal capabilities that were actually
detected.
