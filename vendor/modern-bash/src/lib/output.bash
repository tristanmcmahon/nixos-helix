#!/usr/bin/env bash

modern_bash_output_state_declaration=''
if modern_bash_output_state_declaration=$(declare -p MODERN_BASH_OUTPUT_LOAD_STATE 2>/dev/null) &&
    [[ ${modern_bash_output_state_declaration} == declare\ -a\ * ]] &&
    [[ ${MODERN_BASH_OUTPUT_LOAD_STATE[0]-} == complete ]] &&
    [[ ${MODERN_BASH_OUTPUT_LOADED:-0} == 1 ]] &&
    declare -F modern_bash::output::configure >/dev/null &&
    declare -F modern_bash::output::print >/dev/null; then
    unset modern_bash_output_state_declaration
    return 0
fi
unset modern_bash_output_state_declaration MODERN_BASH_OUTPUT_LOAD_STATE

MODERN_BASH_OUTPUT_LOADED=1
MODERN_BASH_OUTPUT_INITIALIZED=0
MODERN_BASH_OUTPUT_FD=2

modern_bash::output::_message() {
    local message=''

    if (($# > 0)); then
        printf -v message '%s ' "$@"
        message=${message% }
    fi
    printf '%s' "${message}"
}

modern_bash::output::configure() {
    local fd=${1:-2}

    MODERN_BASH_OUTPUT_INITIALIZED=0
    modern_bash::capabilities::detect "${fd}" || return
    modern_bash::theme::init || return
    MODERN_BASH_OUTPUT_FD=${fd}
    MODERN_BASH_OUTPUT_INITIALIZED=1
}

modern_bash::output::_ensure_configured() {
    if [[ ${MODERN_BASH_OUTPUT_INITIALIZED} != 1 ]]; then
        modern_bash::output::configure 2
    fi
}

modern_bash::output::line() {
    local message

    modern_bash::output::_ensure_configured || return
    message=$(modern_bash::output::_message "$@")
    printf '%s\n' "${message}" >&"${MODERN_BASH_OUTPUT_FD}"
}

modern_bash::output::status() {
    local kind=${1:-}
    local style=''
    local icon=''
    local message

    if (($# == 0)); then
        return 2
    fi
    shift
    modern_bash::output::_ensure_configured || return

    case ${kind} in
        info)
            style=${MODERN_BASH_THEME_INFO}
            icon=${MODERN_BASH_THEME_ICON_INFO}
            ;;
        success)
            style=${MODERN_BASH_THEME_SUCCESS}
            icon=${MODERN_BASH_THEME_ICON_SUCCESS}
            ;;
        warning)
            style=${MODERN_BASH_THEME_WARNING}
            icon=${MODERN_BASH_THEME_ICON_WARNING}
            ;;
        error)
            style=${MODERN_BASH_THEME_ERROR}
            icon=${MODERN_BASH_THEME_ICON_ERROR}
            ;;
        debug)
            style=${MODERN_BASH_THEME_DEBUG}
            icon=${MODERN_BASH_THEME_ICON_DEBUG}
            ;;
        *) return 2 ;;
    esac

    message=$(modern_bash::output::_message "$@")
    printf '%s%s%s %s\n' \
        "${style}" \
        "${icon}" \
        "${MODERN_BASH_THEME_RESET}" \
        "${message}" >&"${MODERN_BASH_OUTPUT_FD}"
}

modern_bash::output::heading() {
    local message

    modern_bash::output::_ensure_configured || return
    message=$(modern_bash::output::_message "$@")
    printf '%s%s%s\n' \
        "${MODERN_BASH_THEME_BOLD}" \
        "${message}" \
        "${MODERN_BASH_THEME_RESET}" >&"${MODERN_BASH_OUTPUT_FD}"
}

modern_bash::output::info() {
    modern_bash::output::status info "$@"
}

modern_bash::output::success() {
    modern_bash::output::status success "$@"
}

modern_bash::output::warning() {
    modern_bash::output::status warning "$@"
}

modern_bash::output::error() {
    modern_bash::output::status error "$@"
}

modern_bash::output::debug() {
    case ${MODERN_BASH_DEBUG:-0} in
        1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn])
            modern_bash::output::status debug "$@"
            ;;
    esac
}

# Plain output is intentionally independent of the configured diagnostic
# stream. It is suitable for values consumed by another command.
modern_bash::output::print() {
    local message

    message=$(modern_bash::output::_message "$@")
    printf '%s\n' "${message}"
}

MODERN_BASH_OUTPUT_LOAD_STATE=(complete)
