#!/usr/bin/env bash

modern_bash_capabilities_state_declaration=''
if modern_bash_capabilities_state_declaration=$(declare -p MODERN_BASH_CAPABILITIES_LOAD_STATE 2>/dev/null) &&
    [[ ${modern_bash_capabilities_state_declaration} == declare\ -a\ * ]] &&
    [[ ${MODERN_BASH_CAPABILITIES_LOAD_STATE[0]-} == complete ]] &&
    [[ ${MODERN_BASH_CAPABILITIES_LOADED:-0} == 1 ]] &&
    declare -F modern_bash::capabilities::detect >/dev/null &&
    declare -F modern_bash::capabilities::color_name >/dev/null; then
    unset modern_bash_capabilities_state_declaration
    return 0
fi
unset modern_bash_capabilities_state_declaration MODERN_BASH_CAPABILITIES_LOAD_STATE

MODERN_BASH_CAPABILITIES_LOADED=1
MODERN_BASH_CAPABILITIES_DETECTED=0

# The detected values are deliberately ordinary globals. Callers can inspect
# them after `modern_bash::capabilities::detect FD`, and a later call can refresh
# the snapshot for a different output stream.
MODERN_BASH_CAP_FD=1
MODERN_BASH_CAP_TTY=0
MODERN_BASH_CAP_COLOR_LEVEL=0
MODERN_BASH_CAP_COLOR_SOURCE=undetected
MODERN_BASH_CAP_UNICODE=0
MODERN_BASH_CAP_HYPERLINKS=0
MODERN_BASH_CAP_COLUMNS=80

modern_bash::capabilities::_valid_fd() {
    case ${1:-} in
        ''|*[!0-9]*|0[0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

modern_bash::capabilities::_fd_is_open() {
    local fd=${1:-}

    modern_bash::capabilities::_valid_fd "${fd}" || return 1
    : 2>/dev/null >&"${fd}"
}

modern_bash::capabilities::_automatic_color_level() {
    local colors=''

    case ${COLORTERM:-} in
        *[Tt][Rr][Uu][Ee][Cc][Oo][Ll][Oo][Rr]*|*24[Bb][Ii][Tt]*)
            printf '3\n'
            return 0
            ;;
    esac

    case ${TERM:-} in
        *-[Dd][Ii][Rr][Ee][Cc][Tt]|*[Tt][Rr][Uu][Ee][Cc][Oo][Ll][Oo][Rr]*|*24[Bb][Ii][Tt]*)
            printf '3\n'
            return 0
            ;;
    esac

    if command -v tput >/dev/null 2>&1 && [[ -n ${TERM:-} ]]; then
        if ! colors=$(command tput colors 2>/dev/null); then
            printf '0\n'
            return 0
        fi
        case ${colors} in
            ''|0|0*|*[!0-9]*)
                printf '0\n'
                return 0
                ;;
        esac

        if ((colors >= 16777216)); then
            printf '3\n'
        elif ((colors >= 256)); then
            printf '2\n'
        else
            printf '1\n'
        fi
        return 0
    fi

    # `tput` is optional. With no terminfo probe available, fall back only for
    # terminal families whose colour behaviour is well established.
    case ${TERM:-} in
        *256[Cc][Oo][Ll][Oo][Rr]*) printf '2\n' ;;
        ansi|color|cygwin|linux|rxvt*|screen*|tmux*|vt100*|xterm*) printf '1\n' ;;
        *) printf '0\n' ;;
    esac
}

modern_bash::capabilities::_detect_color() {
    local requested=${MODERN_BASH_COLOR-auto}
    local detected_level=0

    case ${requested} in
        never)
            MODERN_BASH_CAP_COLOR_LEVEL=0
            MODERN_BASH_CAP_COLOR_SOURCE=modern-bash
            return 0
            ;;
        always)
            detected_level=$(modern_bash::capabilities::_automatic_color_level)
            if [[ ${detected_level} == 0 ]]; then
                detected_level=1
            fi
            MODERN_BASH_CAP_COLOR_LEVEL=${detected_level}
            MODERN_BASH_CAP_COLOR_SOURCE=modern-bash
            return 0
            ;;
        auto) ;;
        *) return 2 ;;
    esac

    if [[ ${FORCE_COLOR+x} == x ]]; then
        case ${FORCE_COLOR:-1} in
            0)
                MODERN_BASH_CAP_COLOR_LEVEL=0
                ;;
            1)
                MODERN_BASH_CAP_COLOR_LEVEL=1
                ;;
            2)
                MODERN_BASH_CAP_COLOR_LEVEL=2
                ;;
            3)
                MODERN_BASH_CAP_COLOR_LEVEL=3
                ;;
            *)
                MODERN_BASH_CAP_COLOR_LEVEL=1
                ;;
        esac
        MODERN_BASH_CAP_COLOR_SOURCE=force-color
    elif [[ ${NO_COLOR+x} == x ]]; then
        MODERN_BASH_CAP_COLOR_LEVEL=0
        MODERN_BASH_CAP_COLOR_SOURCE=no-color
    elif ((MODERN_BASH_CAP_TTY == 0)); then
        MODERN_BASH_CAP_COLOR_LEVEL=0
        MODERN_BASH_CAP_COLOR_SOURCE=non-terminal
    else
        case ${TERM:-dumb} in
            [Dd][Uu][Mm][Bb])
                MODERN_BASH_CAP_COLOR_LEVEL=0
                MODERN_BASH_CAP_COLOR_SOURCE=term-dumb
                ;;
            *)
                detected_level=$(modern_bash::capabilities::_automatic_color_level)
                MODERN_BASH_CAP_COLOR_LEVEL=${detected_level}
                MODERN_BASH_CAP_COLOR_SOURCE=terminal
                ;;
        esac
    fi
}

modern_bash::capabilities::_detect_unicode() {
    local requested=${MODERN_BASH_UNICODE-auto}
    local locale_name=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}

    case ${requested} in
        always)
            MODERN_BASH_CAP_UNICODE=1
            ;;
        never)
            MODERN_BASH_CAP_UNICODE=0
            ;;
        auto)
            case ${locale_name} in
                *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) MODERN_BASH_CAP_UNICODE=1 ;;
                *) MODERN_BASH_CAP_UNICODE=0 ;;
            esac
            ;;
        *) return 2 ;;
    esac
}

modern_bash::capabilities::_detect_hyperlinks() {
    local requested=${MODERN_BASH_HYPERLINKS-auto}

    case ${requested} in
        always)
            MODERN_BASH_CAP_HYPERLINKS=1
            return 0
            ;;
        never)
            MODERN_BASH_CAP_HYPERLINKS=0
            return 0
            ;;
        auto) ;;
        *) return 2 ;;
    esac

    MODERN_BASH_CAP_HYPERLINKS=0
    if ((MODERN_BASH_CAP_TTY == 0)); then
        return 0
    fi

    case ${TERM:-dumb} in
        [Dd][Uu][Mm][Bb]) return 0 ;;
    esac

    if [[ -n ${WT_SESSION:-} || -n ${KONSOLE_VERSION:-} || -n ${KITTY_WINDOW_ID:-} || -n ${GHOSTTY_RESOURCES_DIR:-} ]]; then
        MODERN_BASH_CAP_HYPERLINKS=1
        return 0
    fi

    case ${TERM_PROGRAM:-} in
        Apple_Terminal|Hyper|WezTerm|vscode|iTerm.app)
            MODERN_BASH_CAP_HYPERLINKS=1
            ;;
    esac
}

modern_bash::capabilities::_detect_columns() {
    local columns=''

    case ${COLUMNS:-} in
        ''|0*|*[!0-9]*) ;;
        *) columns=${COLUMNS} ;;
    esac

    if [[ -z ${columns} ]] && ((MODERN_BASH_CAP_TTY == 1)) && command -v tput >/dev/null 2>&1 && [[ -n ${TERM:-} ]]; then
        if columns=$(command tput cols 2>/dev/null); then
            case ${columns} in
                ''|0*|*[!0-9]*) columns='' ;;
            esac
        else
            columns=''
        fi
    fi

    MODERN_BASH_CAP_COLUMNS=${columns:-80}
}

modern_bash::capabilities::detect() {
    local fd=${1:-1}

    MODERN_BASH_CAPABILITIES_DETECTED=0
    if ! modern_bash::capabilities::_fd_is_open "${fd}"; then
        return 2
    fi

    MODERN_BASH_CAP_FD=${fd}
    if [[ -t ${fd} ]]; then
        MODERN_BASH_CAP_TTY=1
    else
        MODERN_BASH_CAP_TTY=0
    fi

    modern_bash::capabilities::_detect_color || return
    modern_bash::capabilities::_detect_unicode || return
    modern_bash::capabilities::_detect_hyperlinks || return
    modern_bash::capabilities::_detect_columns
    MODERN_BASH_CAPABILITIES_DETECTED=1
}

modern_bash::capabilities::color_name() {
    local level=${1:-${MODERN_BASH_CAP_COLOR_LEVEL}}

    case ${level} in
        0) printf 'none\n' ;;
        1) printf 'ANSI 16-colour\n' ;;
        2) printf 'ANSI 256-colour\n' ;;
        3) printf '24-bit colour\n' ;;
        *) printf 'unknown\n'; return 2 ;;
    esac
}

MODERN_BASH_CAPABILITIES_LOAD_STATE=(complete)
