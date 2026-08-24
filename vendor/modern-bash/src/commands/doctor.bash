#!/usr/bin/env bash

modern_bash_doctor_state_declaration=''
if modern_bash_doctor_state_declaration=$(declare -p MODERN_BASH_DOCTOR_LOAD_STATE 2>/dev/null) &&
    [[ ${modern_bash_doctor_state_declaration} == declare\ -a\ * ]] &&
    [[ ${MODERN_BASH_DOCTOR_LOAD_STATE[0]-} == complete ]] &&
    [[ ${MODERN_BASH_DOCTOR_LOADED:-0} == 1 ]] &&
    declare -F modern_bash::doctor::run >/dev/null &&
    declare -F modern_bash::doctor::usage >/dev/null; then
    unset modern_bash_doctor_state_declaration
    return 0
fi
unset modern_bash_doctor_state_declaration MODERN_BASH_DOCTOR_LOAD_STATE

MODERN_BASH_DOCTOR_LOADED=1

modern_bash::doctor::usage() {
    cat <<'USAGE'
Usage: modern-bash doctor [--plain]

Inspect the installation, configuration, current process, and terminal
capabilities. The standalone command cannot inspect its parent shell.

Options:
  --plain       Render without ANSI styling or Unicode labels
  -h, --help    Show this help
USAGE
}

modern_bash::doctor::_version_supported() {
    ((BASH_VERSINFO[0] > 3 || (BASH_VERSINFO[0] == 3 && BASH_VERSINFO[1] >= 2)))
}

modern_bash::doctor::_yes_no() {
    if (($1 == 1)); then
        printf 'yes\n'
    else
        printf 'no\n'
    fi
}

modern_bash::doctor::_safe() {
    local value=$1

    value=${value//[[:cntrl:]]/?}
    printf '%s' "${value}"
}

modern_bash::doctor::run() (
    local modern_bash_doctor_option=''
    local modern_bash_doctor_plain=0
    local modern_bash_doctor_failures=0
    local modern_bash_doctor_shell_mode=non-interactive
    local modern_bash_doctor_activation=inactive
    local modern_bash_doctor_tty_description=''
    local modern_bash_doctor_color_description=''
    local modern_bash_doctor_unicode_description=''
    local modern_bash_doctor_hyperlink_description=''
    local modern_bash_doctor_tput_path=''
    local modern_bash_doctor_git_path=''
    local modern_bash_doctor_safe_value=''
    local modern_bash_doctor_config_valid=0
    local modern_bash_doctor_config_error=''
    local modern_bash_doctor_init_path=${MODERN_BASH_SOURCE_DIR}/init.bash
    local modern_bash_doctor_root=${MODERN_BASH_SOURCE_DIR%/src}

    while (($# > 0)); do
        modern_bash_doctor_option=$1
        shift
        case ${modern_bash_doctor_option} in
            --plain)
                modern_bash_doctor_plain=1
                ;;
            -h|--help)
                modern_bash::doctor::usage
                return 0
                ;;
            *)
                printf 'modern-bash doctor: unknown option: %s\n' "${modern_bash_doctor_option}" >&2
                return 64
                ;;
        esac
    done

    # Load configuration before probing capabilities so the report describes the
    # same effective overrides that interactive initialization will use.
    if modern_bash::config::load; then
        modern_bash::config::apply_defaults
        if modern_bash::config::validate && modern_bash::bootstrap::validate_features; then
            modern_bash_doctor_config_valid=1
        else
            modern_bash_doctor_config_error=${MODERN_BASH_CONFIG_ERROR:-${MODERN_BASH_INIT_ERROR}}
        fi
    else
        modern_bash_doctor_config_error=${MODERN_BASH_CONFIG_ERROR}
    fi

    # Plain mode controls presentation only; it must not change the facts that
    # the report describes.
    if ! modern_bash::capabilities::detect 1; then
        modern_bash_doctor_safe_value=$(modern_bash::doctor::_safe \
            "${modern_bash_doctor_config_error:-invalid capability override}")
        printf 'modern-bash doctor: invalid capability override: %s\n' \
            "${modern_bash_doctor_safe_value}" >&2
        return 64
    fi
    if [[ ${modern_bash_doctor_plain} == 1 ]]; then
        modern_bash::theme::init 0 0 || return 1
    else
        modern_bash::theme::init || return 1
    fi
    MODERN_BASH_OUTPUT_FD=1
    MODERN_BASH_OUTPUT_INITIALIZED=1

    modern_bash::output::heading 'Modern Bash doctor'
    modern_bash::output::line
    modern_bash::output::info "Version: ${MODERN_BASH_VERSION}"
    modern_bash_doctor_safe_value=$(modern_bash::doctor::_safe "${modern_bash_doctor_root}")
    modern_bash::output::info "Runtime root: ${modern_bash_doctor_safe_value}"

    if modern_bash::doctor::_version_supported; then
        modern_bash::output::success "Bash: ${BASH_VERSION} (supported; minimum 3.2)"
    else
        modern_bash::output::error "Bash: ${BASH_VERSION} (3.2 or newer is required)"
        modern_bash_doctor_failures=$((modern_bash_doctor_failures + 1))
    fi

    case $- in
        *i*) modern_bash_doctor_shell_mode=interactive ;;
    esac
    if [[ ${MODERN_BASH_INITIALIZED:-0} == 1 ]]; then
        modern_bash_doctor_activation=active
    fi
    modern_bash::output::info "Current process: ${modern_bash_doctor_shell_mode}"
    modern_bash::output::info "Activation in this process: ${modern_bash_doctor_activation}"

    modern_bash_doctor_tty_description=$(modern_bash::doctor::_yes_no "${MODERN_BASH_CAP_TTY}")
    modern_bash::output::info "Output is a terminal: ${modern_bash_doctor_tty_description} (fd ${MODERN_BASH_CAP_FD})"

    modern_bash_doctor_color_description=$(modern_bash::capabilities::color_name)
    modern_bash::output::info "Colour: ${modern_bash_doctor_color_description} (${MODERN_BASH_CAP_COLOR_SOURCE})"

    modern_bash_doctor_unicode_description=$(modern_bash::doctor::_yes_no "${MODERN_BASH_CAP_UNICODE}")
    modern_bash::output::info "UTF-8 symbols: ${modern_bash_doctor_unicode_description}"

    modern_bash_doctor_hyperlink_description=$(modern_bash::doctor::_yes_no "${MODERN_BASH_CAP_HYPERLINKS}")
    modern_bash::output::info "Terminal hyperlinks: ${modern_bash_doctor_hyperlink_description}"
    modern_bash::output::info "Terminal width: ${MODERN_BASH_CAP_COLUMNS} columns"
    modern_bash_doctor_safe_value=$(modern_bash::doctor::_safe "${TERM:-unset}")
    modern_bash::output::info "TERM: ${modern_bash_doctor_safe_value}"

    if modern_bash_doctor_tput_path=$(command -v tput 2>/dev/null); then
        modern_bash_doctor_safe_value=$(modern_bash::doctor::_safe "${modern_bash_doctor_tput_path}")
        modern_bash::output::success "Optional dependency tput: ${modern_bash_doctor_safe_value}"
    else
        modern_bash::output::info 'Optional dependency tput: unavailable (fallbacks active)'
    fi

    modern_bash_doctor_safe_value=$(modern_bash::doctor::_safe "${modern_bash_doctor_init_path}")
    if [[ -f ${modern_bash_doctor_init_path} && -r ${modern_bash_doctor_init_path} ]]; then
        modern_bash::output::success "Interactive init: ${modern_bash_doctor_safe_value}"
    else
        modern_bash::output::error "Interactive init: unavailable at ${modern_bash_doctor_safe_value}"
        modern_bash_doctor_failures=$((modern_bash_doctor_failures + 1))
    fi

    if [[ ${modern_bash_doctor_config_valid} == 1 ]]; then
        if [[ ${MODERN_BASH_CONFIG_FOUND} == 1 ]]; then
            modern_bash_doctor_safe_value=$(modern_bash::doctor::_safe "${MODERN_BASH_CONFIG_PATH}")
            modern_bash::output::success "Configuration: ${modern_bash_doctor_safe_value}"
        elif [[ -n ${MODERN_BASH_CONFIG_PATH} ]]; then
            modern_bash_doctor_safe_value=$(modern_bash::doctor::_safe "${MODERN_BASH_CONFIG_PATH}")
            modern_bash::output::info "Configuration: ${modern_bash_doctor_safe_value} (not present; defaults active)"
        elif [[ ${MODERN_BASH_CONFIG_DISABLED} == 1 ]]; then
            modern_bash::output::info 'Configuration: disabled; defaults active'
        else
            modern_bash::output::info 'Configuration: no path resolved; defaults active'
        fi

        if modern_bash::bootstrap::feature_enabled prompt; then
            modern_bash::output::success 'Prompt feature (configured): enabled'
        else
            modern_bash::output::info 'Prompt feature (configured): disabled'
        fi
    else
        modern_bash_doctor_safe_value=$(modern_bash::doctor::_safe \
            "${modern_bash_doctor_config_error}")
        modern_bash::output::error "Configuration: ${modern_bash_doctor_safe_value}"
        modern_bash_doctor_failures=$((modern_bash_doctor_failures + 1))
    fi

    if modern_bash_doctor_git_path=$(command -v git 2>/dev/null); then
        modern_bash_doctor_safe_value=$(modern_bash::doctor::_safe "${modern_bash_doctor_git_path}")
        modern_bash::output::success "Optional dependency git: ${modern_bash_doctor_safe_value}"
    else
        modern_bash::output::info 'Optional dependency git: unavailable (Git prompt segment disabled)'
    fi

    modern_bash::output::line
    if ((modern_bash_doctor_failures == 0)); then
        modern_bash::output::success 'Summary: ready (0 failures)'
    else
        modern_bash::output::error "Summary: ${modern_bash_doctor_failures} failure(s)"
        return 1
    fi
)

MODERN_BASH_DOCTOR_LOAD_STATE=(complete)
