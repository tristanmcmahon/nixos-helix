#!/usr/bin/env bash

modern_bash_theme_state_declaration=''
if modern_bash_theme_state_declaration=$(declare -p MODERN_BASH_THEME_LOAD_STATE 2>/dev/null) &&
    [[ ${modern_bash_theme_state_declaration} == declare\ -a\ * ]] &&
    [[ ${MODERN_BASH_THEME_LOAD_STATE[0]-} == complete ]] &&
    [[ ${MODERN_BASH_THEME_LOADED:-0} == 1 ]] &&
    declare -F modern_bash::theme::init >/dev/null; then
    unset modern_bash_theme_state_declaration
    return 0
fi
unset modern_bash_theme_state_declaration MODERN_BASH_THEME_LOAD_STATE

MODERN_BASH_THEME_LOADED=1
MODERN_BASH_THEME_INITIALIZED=0

MODERN_BASH_THEME_RESET=''
MODERN_BASH_THEME_BOLD=''
MODERN_BASH_THEME_DIM=''
MODERN_BASH_THEME_INFO=''
MODERN_BASH_THEME_SUCCESS=''
MODERN_BASH_THEME_WARNING=''
MODERN_BASH_THEME_ERROR=''
MODERN_BASH_THEME_DEBUG=''
MODERN_BASH_THEME_ICON_INFO='i'
MODERN_BASH_THEME_ICON_SUCCESS='ok'
MODERN_BASH_THEME_ICON_WARNING='!'
MODERN_BASH_THEME_ICON_ERROR='x'
MODERN_BASH_THEME_ICON_DEBUG='.'

modern_bash::theme::init() {
    local color_level=${1:-${MODERN_BASH_CAP_COLOR_LEVEL:-0}}
    local unicode=${2:-${MODERN_BASH_CAP_UNICODE:-0}}

    MODERN_BASH_THEME_INITIALIZED=0
    MODERN_BASH_THEME_RESET=''
    MODERN_BASH_THEME_BOLD=''
    MODERN_BASH_THEME_DIM=''
    MODERN_BASH_THEME_INFO=''
    MODERN_BASH_THEME_SUCCESS=''
    MODERN_BASH_THEME_WARNING=''
    MODERN_BASH_THEME_ERROR=''
    MODERN_BASH_THEME_DEBUG=''

    case ${color_level} in
        0) ;;
        1)
            MODERN_BASH_THEME_RESET=$'\033[0m'
            MODERN_BASH_THEME_BOLD=$'\033[1m'
            MODERN_BASH_THEME_DIM=$'\033[2m'
            MODERN_BASH_THEME_INFO=$'\033[34m'
            MODERN_BASH_THEME_SUCCESS=$'\033[32m'
            MODERN_BASH_THEME_WARNING=$'\033[33m'
            MODERN_BASH_THEME_ERROR=$'\033[31m'
            MODERN_BASH_THEME_DEBUG=$'\033[35m'
            ;;
        2)
            MODERN_BASH_THEME_RESET=$'\033[0m'
            MODERN_BASH_THEME_BOLD=$'\033[1m'
            MODERN_BASH_THEME_DIM=$'\033[2m'
            MODERN_BASH_THEME_INFO=$'\033[38;5;75m'
            MODERN_BASH_THEME_SUCCESS=$'\033[38;5;78m'
            MODERN_BASH_THEME_WARNING=$'\033[38;5;214m'
            MODERN_BASH_THEME_ERROR=$'\033[38;5;203m'
            MODERN_BASH_THEME_DEBUG=$'\033[38;5;141m'
            ;;
        3)
            MODERN_BASH_THEME_RESET=$'\033[0m'
            MODERN_BASH_THEME_BOLD=$'\033[1m'
            MODERN_BASH_THEME_DIM=$'\033[2m'
            MODERN_BASH_THEME_INFO=$'\033[38;2;86;156;214m'
            MODERN_BASH_THEME_SUCCESS=$'\033[38;2;80;200;120m'
            MODERN_BASH_THEME_WARNING=$'\033[38;2;230;175;70m'
            MODERN_BASH_THEME_ERROR=$'\033[38;2;235;95;95m'
            MODERN_BASH_THEME_DEBUG=$'\033[38;2;175;135;225m'
            ;;
        *) return 2 ;;
    esac

    case ${unicode} in
        0)
            MODERN_BASH_THEME_ICON_INFO='i'
            MODERN_BASH_THEME_ICON_SUCCESS='ok'
            MODERN_BASH_THEME_ICON_WARNING='!'
            MODERN_BASH_THEME_ICON_ERROR='x'
            MODERN_BASH_THEME_ICON_DEBUG='.'
            ;;
        1)
            MODERN_BASH_THEME_ICON_INFO='ℹ'
            MODERN_BASH_THEME_ICON_SUCCESS='✓'
            MODERN_BASH_THEME_ICON_WARNING='⚠'
            MODERN_BASH_THEME_ICON_ERROR='✗'
            MODERN_BASH_THEME_ICON_DEBUG='·'
            ;;
        *) return 2 ;;
    esac

    MODERN_BASH_THEME_INITIALIZED=1
}

MODERN_BASH_THEME_LOAD_STATE=(complete)
