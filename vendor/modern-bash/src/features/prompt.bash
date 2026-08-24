#!/usr/bin/env bash

modern_bash_prompt_state_declaration=''
if modern_bash_prompt_state_declaration=$(declare -p MODERN_BASH_PROMPT_LOAD_STATE 2>/dev/null) &&
    [[ ${modern_bash_prompt_state_declaration} == declare\ -a\ * ]] &&
    [[ ${MODERN_BASH_PROMPT_LOAD_STATE[0]-} == complete ]] &&
    [[ ${MODERN_BASH_PROMPT_LOADED:-0} == 1 ]] &&
    declare -F modern_bash::prompt::enable >/dev/null &&
    declare -F modern_bash::prompt::disable >/dev/null; then
    unset modern_bash_prompt_state_declaration
    return 0
fi
unset modern_bash_prompt_state_declaration MODERN_BASH_PROMPT_LOAD_STATE

MODERN_BASH_PROMPT_LOADED=1
MODERN_BASH_PROMPT_ENABLED=0
MODERN_BASH_PROMPT_ERROR=''
MODERN_BASH_PROMPT_ORIGINAL_PS1_SET=0
MODERN_BASH_PROMPT_ORIGINAL_PS1_WAS_SET=0
MODERN_BASH_PROMPT_ORIGINAL_PS1=''
MODERN_BASH_PROMPT_ORIGINAL_COMMAND_SET=0
MODERN_BASH_PROMPT_COMMAND_WAS_ARRAY=0
MODERN_BASH_PROMPT_ORIGINAL_COMMAND=''
MODERN_BASH_PROMPT_ORIGINAL_COMMANDS=()
MODERN_BASH_PROMPT_INSTALLED_COMMAND=''
MODERN_BASH_PROMPT_INSTALLED_COMMANDS=()
MODERN_BASH_PROMPT_ACTIVE_PS1=''
MODERN_BASH_PROMPT_LAST_STATUS=0
MODERN_BASH_PROMPT_STATUS_SEGMENT=''
MODERN_BASH_PROMPT_CWD=''
MODERN_BASH_PROMPT_GIT_SEGMENT=''
MODERN_BASH_PROMPT_THEME_RESET=''
MODERN_BASH_PROMPT_THEME_INFO=''
MODERN_BASH_PROMPT_THEME_SUCCESS=''
MODERN_BASH_PROMPT_THEME_ERROR=''
MODERN_BASH_PROMPT_THEME_DEBUG=''
MODERN_BASH_PROMPT_UNICODE=0
MODERN_BASH_PROMPT_STYLE_RESET=''
MODERN_BASH_PROMPT_STYLE_INFO=''
MODERN_BASH_PROMPT_STYLE_SUCCESS=''
MODERN_BASH_PROMPT_STYLE_ERROR=''
MODERN_BASH_PROMPT_STYLE_DEBUG=''

modern_bash::prompt::_sanitize() {
    local value=$1

    value=${value//[[:cntrl:]]/?}
    printf '%s' "${value}"
}

modern_bash::prompt::_cwd() {
    local cwd=${PWD:-?}

    if [[ -n ${HOME:-} ]]; then
        case ${cwd} in
            "${HOME}") cwd='~' ;;
            "${HOME}"/*) cwd="~/${cwd#"${HOME}"/}" ;;
        esac
    fi
    modern_bash::prompt::_sanitize "${cwd}"
}

modern_bash::prompt::_update_cwd() {
    local cwd=${PWD:-?}

    if [[ -n ${HOME:-} ]]; then
        case ${cwd} in
            "${HOME}") cwd='~' ;;
            "${HOME}"/*) cwd="~/${cwd#"${HOME}"/}" ;;
        esac
    fi
    cwd=${cwd//[[:cntrl:]]/?}
    MODERN_BASH_PROMPT_CWD=${cwd}
}

modern_bash::prompt::_git_branch() {
    local branch=''
    local commit=''
    local git_status=0

    if ! command -v git >/dev/null 2>&1; then
        return 0
    fi

    if branch=$(GIT_OPTIONAL_LOCKS=0 command git symbolic-ref --quiet --short HEAD 2>/dev/null); then
        git_status=0
    else
        git_status=$?
    fi
    if ((git_status == 1)); then
        commit=$(GIT_OPTIONAL_LOCKS=0 command git rev-parse --short HEAD 2>/dev/null) || return 0
        branch=@${commit}
    elif ((git_status != 0)); then
        return 0
    fi
    modern_bash::prompt::_sanitize "${branch}"
}

modern_bash::prompt::_style() {
    local ansi=$1

    if [[ -n ${ansi} ]]; then
        printf '\\[%s\\]' "${ansi}"
    fi
}

modern_bash::prompt::_prepare_theme() {
    local saved_capabilities_detected=${MODERN_BASH_CAPABILITIES_DETECTED}
    local saved_cap_fd=${MODERN_BASH_CAP_FD}
    local saved_cap_tty=${MODERN_BASH_CAP_TTY}
    local saved_cap_color_level=${MODERN_BASH_CAP_COLOR_LEVEL}
    local saved_cap_color_source=${MODERN_BASH_CAP_COLOR_SOURCE}
    local saved_cap_unicode=${MODERN_BASH_CAP_UNICODE}
    local saved_cap_hyperlinks=${MODERN_BASH_CAP_HYPERLINKS}
    local saved_cap_columns=${MODERN_BASH_CAP_COLUMNS}
    local saved_theme_initialized=${MODERN_BASH_THEME_INITIALIZED}
    local saved_theme_reset=${MODERN_BASH_THEME_RESET}
    local saved_theme_bold=${MODERN_BASH_THEME_BOLD}
    local saved_theme_dim=${MODERN_BASH_THEME_DIM}
    local saved_theme_info=${MODERN_BASH_THEME_INFO}
    local saved_theme_success=${MODERN_BASH_THEME_SUCCESS}
    local saved_theme_warning=${MODERN_BASH_THEME_WARNING}
    local saved_theme_error=${MODERN_BASH_THEME_ERROR}
    local saved_theme_debug=${MODERN_BASH_THEME_DEBUG}
    local saved_icon_info=${MODERN_BASH_THEME_ICON_INFO}
    local saved_icon_success=${MODERN_BASH_THEME_ICON_SUCCESS}
    local saved_icon_warning=${MODERN_BASH_THEME_ICON_WARNING}
    local saved_icon_error=${MODERN_BASH_THEME_ICON_ERROR}
    local saved_icon_debug=${MODERN_BASH_THEME_ICON_DEBUG}
    local status=0

    modern_bash::capabilities::detect 2 || status=$?
    if ((status == 0)); then
        modern_bash::theme::init || status=$?
    fi
    if ((status == 0)); then
        MODERN_BASH_PROMPT_THEME_RESET=${MODERN_BASH_THEME_RESET}
        MODERN_BASH_PROMPT_THEME_INFO=${MODERN_BASH_THEME_INFO}
        MODERN_BASH_PROMPT_THEME_SUCCESS=${MODERN_BASH_THEME_SUCCESS}
        MODERN_BASH_PROMPT_THEME_ERROR=${MODERN_BASH_THEME_ERROR}
        MODERN_BASH_PROMPT_THEME_DEBUG=${MODERN_BASH_THEME_DEBUG}
        MODERN_BASH_PROMPT_UNICODE=${MODERN_BASH_CAP_UNICODE}
        MODERN_BASH_PROMPT_STYLE_RESET=$(modern_bash::prompt::_style "${MODERN_BASH_PROMPT_THEME_RESET}")
        MODERN_BASH_PROMPT_STYLE_INFO=$(modern_bash::prompt::_style "${MODERN_BASH_PROMPT_THEME_INFO}")
        MODERN_BASH_PROMPT_STYLE_SUCCESS=$(modern_bash::prompt::_style "${MODERN_BASH_PROMPT_THEME_SUCCESS}")
        MODERN_BASH_PROMPT_STYLE_ERROR=$(modern_bash::prompt::_style "${MODERN_BASH_PROMPT_THEME_ERROR}")
        MODERN_BASH_PROMPT_STYLE_DEBUG=$(modern_bash::prompt::_style "${MODERN_BASH_PROMPT_THEME_DEBUG}")
    fi

    MODERN_BASH_CAPABILITIES_DETECTED=${saved_capabilities_detected}
    MODERN_BASH_CAP_FD=${saved_cap_fd}
    MODERN_BASH_CAP_TTY=${saved_cap_tty}
    MODERN_BASH_CAP_COLOR_LEVEL=${saved_cap_color_level}
    MODERN_BASH_CAP_COLOR_SOURCE=${saved_cap_color_source}
    MODERN_BASH_CAP_UNICODE=${saved_cap_unicode}
    MODERN_BASH_CAP_HYPERLINKS=${saved_cap_hyperlinks}
    MODERN_BASH_CAP_COLUMNS=${saved_cap_columns}
    MODERN_BASH_THEME_INITIALIZED=${saved_theme_initialized}
    MODERN_BASH_THEME_RESET=${saved_theme_reset}
    MODERN_BASH_THEME_BOLD=${saved_theme_bold}
    MODERN_BASH_THEME_DIM=${saved_theme_dim}
    MODERN_BASH_THEME_INFO=${saved_theme_info}
    MODERN_BASH_THEME_SUCCESS=${saved_theme_success}
    MODERN_BASH_THEME_WARNING=${saved_theme_warning}
    MODERN_BASH_THEME_ERROR=${saved_theme_error}
    MODERN_BASH_THEME_DEBUG=${saved_theme_debug}
    MODERN_BASH_THEME_ICON_INFO=${saved_icon_info}
    MODERN_BASH_THEME_ICON_SUCCESS=${saved_icon_success}
    MODERN_BASH_THEME_ICON_WARNING=${saved_icon_warning}
    MODERN_BASH_THEME_ICON_ERROR=${saved_icon_error}
    MODERN_BASH_THEME_ICON_DEBUG=${saved_icon_debug}

    return "${status}"
}

modern_bash::prompt::_build_ps1() {
    local status=$1
    local status_style=''
    local cwd_style
    local git_style
    local symbol_style
    local reset_style
    local separator=' '
    local symbol='>'

    cwd_style=${MODERN_BASH_PROMPT_STYLE_INFO}
    git_style=${MODERN_BASH_PROMPT_STYLE_DEBUG}
    symbol_style=${MODERN_BASH_PROMPT_STYLE_SUCCESS}
    reset_style=${MODERN_BASH_PROMPT_STYLE_RESET}

    if [[ ${MODERN_BASH_PROMPT_UNICODE} == 1 ]]; then
        symbol='❯'
    fi
    if [[ ${status} == 0 ]]; then
        status_style=${MODERN_BASH_PROMPT_STYLE_SUCCESS}
    else
        status_style=${MODERN_BASH_PROMPT_STYLE_ERROR}
    fi
    if [[ ${MODERN_BASH_PROMPT_MULTILINE} == 1 ]]; then
        separator='\n'
    fi

    # Dynamic text remains in variables and is expanded once by Bash. It is
    # never interpolated into PS1, so branch names and paths cannot inject a
    # second command substitution during prompt expansion.
    PS1="${status_style}"'${MODERN_BASH_PROMPT_STATUS_SEGMENT}'\
"${reset_style}${cwd_style}"'${MODERN_BASH_PROMPT_CWD}'\
"${reset_style}${git_style}"'${MODERN_BASH_PROMPT_GIT_SEGMENT}'\
"${reset_style}${separator}${symbol_style}${symbol}${reset_style} "
    MODERN_BASH_PROMPT_ACTIVE_PS1=${PS1}
}

modern_bash::prompt::render() {
    local status=${1-0}
    local branch=''

    MODERN_BASH_PROMPT_ERROR=''
    # Arithmetic contexts recursively evaluate variable contents. Validate and
    # canonicalize this public argument before it reaches prompt construction so
    # a crafted value cannot turn an array subscript into command execution.
    case ${status} in
        ''|*[!0-9]*)
            MODERN_BASH_PROMPT_ERROR='prompt status must be a decimal exit status from 0 to 255'
            return 2
            ;;
    esac
    while [[ ${status} == 0?* ]]; do
        status=${status#0}
    done
    case ${status} in
        [0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5]) ;;
        *)
            MODERN_BASH_PROMPT_ERROR='prompt status must be a decimal exit status from 0 to 255'
            return 2
            ;;
    esac

    MODERN_BASH_PROMPT_STATUS_SEGMENT=''
    case ${MODERN_BASH_PROMPT_STATUS} in
        always) MODERN_BASH_PROMPT_STATUS_SEGMENT="[${status}] " ;;
        nonzero)
            if ((status != 0)); then
                MODERN_BASH_PROMPT_STATUS_SEGMENT="[${status}] "
            fi
            ;;
    esac

    modern_bash::prompt::_update_cwd
    MODERN_BASH_PROMPT_GIT_SEGMENT=''
    if [[ ${MODERN_BASH_PROMPT_GIT} == 1 ]]; then
        branch=$(modern_bash::prompt::_git_branch)
        if [[ -n ${branch} ]]; then
            MODERN_BASH_PROMPT_GIT_SEGMENT=" (${branch})"
        fi
    fi
    modern_bash::prompt::_build_ps1 "${status}"
}

modern_bash::prompt::update() {
    MODERN_BASH_PROMPT_LAST_STATUS=$?
    modern_bash::prompt::render "${MODERN_BASH_PROMPT_LAST_STATUS}"
    return 0
}

modern_bash::prompt::capture_status() {
    MODERN_BASH_PROMPT_LAST_STATUS=$?
    return 0
}

modern_bash::prompt::_restore_status() {
    return "${MODERN_BASH_PROMPT_LAST_STATUS}"
}

modern_bash::prompt::render_captured() {
    modern_bash::prompt::render "${MODERN_BASH_PROMPT_LAST_STATUS}"
    return 0
}

modern_bash::prompt::_supports_prompt_command_array() {
    ((BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1)))
}

modern_bash::prompt::_variable_attributes() {
    local declaration=''
    local attributes=''

    if ! declaration=$(declare -p "$1" 2>/dev/null); then
        return 1
    fi
    declaration=${declaration#declare }
    attributes=${declaration%% *}
    printf '%s\n' "${attributes}"
}

modern_bash::prompt::_validate_target_variables() {
    local attributes=''

    if attributes=$(modern_bash::prompt::_variable_attributes PS1); then
        case ${attributes} in
            -*[rniAaltu]*)
                MODERN_BASH_PROMPT_ERROR='PS1 has unsupported readonly, special, case-transform, or array attributes'
                return 2
                ;;
        esac
    fi

    if attributes=$(modern_bash::prompt::_variable_attributes PROMPT_COMMAND); then
        case ${attributes} in
            -*A*)
                MODERN_BASH_PROMPT_ERROR='associative PROMPT_COMMAND values are not supported'
                return 2
                ;;
            -*[rniltu]*)
                MODERN_BASH_PROMPT_ERROR='PROMPT_COMMAND has unsupported readonly, special, or case-transform attributes'
                return 2
                ;;
        esac
    fi
}

modern_bash::prompt::_compose_hook() {
    local original_command=$1

    if modern_bash::prompt::_hook_is_comment_only "${original_command}"; then
        MODERN_BASH_PROMPT_INSTALLED_COMMAND=${original_command}
    else
        MODERN_BASH_PROMPT_INSTALLED_COMMAND=$'if modern_bash::prompt::_restore_status; then\n'\
"${original_command}"$'\nelse\n'"${original_command}"$'\nfi'
    fi
}

modern_bash::prompt::_hook_is_comment_only() {
    local remaining=$1
    local line=''
    local trimmed=''

    while :; do
        case ${remaining} in
            *$'\n'*)
                line=${remaining%%$'\n'*}
                remaining=${remaining#*$'\n'}
                ;;
            *)
                line=${remaining}
                remaining=''
                ;;
        esac
        trimmed=${line#"${line%%[![:space:]]*}"}
        case ${trimmed} in
            ''|'#'*) ;;
            *) return 1 ;;
        esac
        [[ -n ${remaining} ]] || return 0
    done
}

modern_bash::prompt::_install_hook() {
    local prompt_command_declaration=''
    local declaration_prefix=''
    local original_command=''
    local composed_command=''
    local wrapped_command=''
    local command_index=''
    local command_values=()

    if prompt_command_declaration=$(declare -p PROMPT_COMMAND 2>/dev/null); then
        MODERN_BASH_PROMPT_ORIGINAL_COMMAND_SET=1
        declaration_prefix=${prompt_command_declaration%% PROMPT_COMMAND=*}
    else
        MODERN_BASH_PROMPT_ORIGINAL_COMMAND_SET=0
    fi

    case ${declaration_prefix} in
        'declare -'*a*)
            MODERN_BASH_PROMPT_COMMAND_WAS_ARRAY=1
            MODERN_BASH_PROMPT_ORIGINAL_COMMANDS=()
            for command_index in "${!PROMPT_COMMAND[@]}"; do
                MODERN_BASH_PROMPT_ORIGINAL_COMMANDS[command_index]=${PROMPT_COMMAND[command_index]}
            done
            if modern_bash::prompt::_supports_prompt_command_array; then
                if ((${#PROMPT_COMMAND[@]} > 0)); then
                    # Flatten values before adding our own hooks. Array slices
                    # use numeric subscripts for sparse arrays, not ordinal
                    # positions, which could otherwise duplicate the first hook.
                    command_values=("${PROMPT_COMMAND[@]}")
                    modern_bash::prompt::_compose_hook "${command_values[0]}"
                    wrapped_command=${MODERN_BASH_PROMPT_INSTALLED_COMMAND}
                    PROMPT_COMMAND=(modern_bash::prompt::capture_status "${wrapped_command}" \
                        "${command_values[@]:1}" modern_bash::prompt::render_captured)
                else
                    PROMPT_COMMAND=(modern_bash::prompt::update)
                fi
                MODERN_BASH_PROMPT_INSTALLED_COMMANDS=()
                for command_index in "${!PROMPT_COMMAND[@]}"; do
                    MODERN_BASH_PROMPT_INSTALLED_COMMANDS[command_index]=${PROMPT_COMMAND[command_index]}
                done
                return
            fi
            original_command=${PROMPT_COMMAND[0]-}
            MODERN_BASH_PROMPT_ORIGINAL_COMMAND=${original_command}
            if [[ -n ${original_command} ]]; then
                modern_bash::prompt::_compose_hook "${original_command}"
                composed_command=$'modern_bash::prompt::capture_status\n'\
"${MODERN_BASH_PROMPT_INSTALLED_COMMAND}"$'\nmodern_bash::prompt::render_captured'
            else
                composed_command='modern_bash::prompt::update'
            fi
            PROMPT_COMMAND[0]=${composed_command}
            MODERN_BASH_PROMPT_INSTALLED_COMMANDS=()
            for command_index in "${!PROMPT_COMMAND[@]}"; do
                MODERN_BASH_PROMPT_INSTALLED_COMMANDS[command_index]=${PROMPT_COMMAND[command_index]}
            done
            return
            ;;
    esac

    MODERN_BASH_PROMPT_COMMAND_WAS_ARRAY=0
    original_command=${PROMPT_COMMAND:-}
    MODERN_BASH_PROMPT_ORIGINAL_COMMAND=${original_command}
    if [[ -n ${original_command} ]]; then
        modern_bash::prompt::_compose_hook "${original_command}"
        composed_command=$'modern_bash::prompt::capture_status\n'\
"${MODERN_BASH_PROMPT_INSTALLED_COMMAND}"$'\nmodern_bash::prompt::render_captured'
        PROMPT_COMMAND=${composed_command}
    else
        PROMPT_COMMAND='modern_bash::prompt::update'
    fi
    MODERN_BASH_PROMPT_INSTALLED_COMMAND=${PROMPT_COMMAND}
}

modern_bash::prompt::_hook_is_owned() {
    local prompt_command_declaration=''
    local declaration_prefix=''
    local index=0
    local command_index=''
    local installed_index=''
    local prompt_command_indices=()
    local installed_command_indices=()

    if ! prompt_command_declaration=$(declare -p PROMPT_COMMAND 2>/dev/null); then
        return 1
    fi
    declaration_prefix=${prompt_command_declaration%% PROMPT_COMMAND=*}

    if [[ ${MODERN_BASH_PROMPT_COMMAND_WAS_ARRAY} == 1 ]]; then
        case ${declaration_prefix} in
            'declare -'*a*) ;;
            *) return 1 ;;
        esac
        if ((${#PROMPT_COMMAND[@]} != ${#MODERN_BASH_PROMPT_INSTALLED_COMMANDS[@]})); then
            return 1
        fi
        prompt_command_indices=("${!PROMPT_COMMAND[@]}")
        installed_command_indices=("${!MODERN_BASH_PROMPT_INSTALLED_COMMANDS[@]}")
        while ((index < ${#prompt_command_indices[@]})); do
            command_index=${prompt_command_indices[index]}
            installed_index=${installed_command_indices[index]}
            if [[ ${command_index} != "${installed_index}" || \
                ${PROMPT_COMMAND[command_index]} != "${MODERN_BASH_PROMPT_INSTALLED_COMMANDS[installed_index]}" ]]; then
                return 1
            fi
            index=$((index + 1))
        done
        return 0
    fi

    case ${declaration_prefix} in
        'declare -'*a*|'declare -'*A*) return 1 ;;
    esac
    [[ ${PROMPT_COMMAND} == "${MODERN_BASH_PROMPT_INSTALLED_COMMAND}" ]]
}

modern_bash::prompt::_clear_snapshot() {
    MODERN_BASH_PROMPT_ORIGINAL_PS1_SET=0
    MODERN_BASH_PROMPT_ORIGINAL_PS1_WAS_SET=0
    MODERN_BASH_PROMPT_ORIGINAL_PS1=''
    MODERN_BASH_PROMPT_ORIGINAL_COMMAND_SET=0
    MODERN_BASH_PROMPT_COMMAND_WAS_ARRAY=0
    MODERN_BASH_PROMPT_ORIGINAL_COMMAND=''
    MODERN_BASH_PROMPT_ORIGINAL_COMMANDS=()
    MODERN_BASH_PROMPT_INSTALLED_COMMAND=''
    MODERN_BASH_PROMPT_INSTALLED_COMMANDS=()
    MODERN_BASH_PROMPT_ACTIVE_PS1=''
}

modern_bash::prompt::disable() {
    local attributes=''
    local command_index=''

    if [[ ${MODERN_BASH_PROMPT_ENABLED} != 1 ]]; then
        return 0
    fi

    MODERN_BASH_PROMPT_ERROR=''
    if ! modern_bash::prompt::_hook_is_owned; then
        MODERN_BASH_PROMPT_ERROR='PROMPT_COMMAND changed after Modern Bash was enabled; refusing to overwrite it'
        return 1
    fi
    if attributes=$(modern_bash::prompt::_variable_attributes PROMPT_COMMAND); then
        case ${attributes} in
            -*r*)
                MODERN_BASH_PROMPT_ERROR='PROMPT_COMMAND became readonly; it cannot be restored'
                return 1
                ;;
        esac
    fi
    if [[ ${PS1-} == "${MODERN_BASH_PROMPT_ACTIVE_PS1}" ]] && \
        attributes=$(modern_bash::prompt::_variable_attributes PS1); then
        case ${attributes} in
            -*r*)
                MODERN_BASH_PROMPT_ERROR='PS1 became readonly; it cannot be restored'
                return 1
                ;;
        esac
    fi

    if [[ ${MODERN_BASH_PROMPT_COMMAND_WAS_ARRAY} == 1 ]]; then
        PROMPT_COMMAND=()
        for command_index in "${!MODERN_BASH_PROMPT_ORIGINAL_COMMANDS[@]}"; do
            PROMPT_COMMAND[command_index]=${MODERN_BASH_PROMPT_ORIGINAL_COMMANDS[command_index]}
        done
    elif [[ ${MODERN_BASH_PROMPT_ORIGINAL_COMMAND_SET} == 1 ]]; then
        PROMPT_COMMAND=${MODERN_BASH_PROMPT_ORIGINAL_COMMAND}
    else
        unset PROMPT_COMMAND
    fi

    # Preserve a prompt installed by another tool after Modern Bash. Otherwise,
    # put back the exact original value, including its unset state.
    if [[ ${PS1-} == "${MODERN_BASH_PROMPT_ACTIVE_PS1}" ]]; then
        if [[ ${MODERN_BASH_PROMPT_ORIGINAL_PS1_WAS_SET} == 1 ]]; then
            PS1=${MODERN_BASH_PROMPT_ORIGINAL_PS1}
        else
            unset PS1
        fi
    fi

    MODERN_BASH_PROMPT_ENABLED=0
    modern_bash::prompt::_clear_snapshot
}

modern_bash::prompt::enable() {
    if [[ ${MODERN_BASH_PROMPT_ENABLED} == 1 ]]; then
        return 0
    fi

    MODERN_BASH_PROMPT_ERROR=''
    if ! shopt -q promptvars; then
        MODERN_BASH_PROMPT_ERROR='Bash promptvars must be enabled for the prompt feature'
        return 1
    fi
    if ! modern_bash::prompt::_validate_target_variables; then
        return 1
    fi
    if ! modern_bash::prompt::_prepare_theme; then
        MODERN_BASH_PROMPT_ERROR='terminal capability detection failed for the prompt'
        return 1
    fi

    if [[ ${MODERN_BASH_PROMPT_ORIGINAL_PS1_SET} != 1 ]]; then
        if [[ ${PS1+x} == x ]]; then
            MODERN_BASH_PROMPT_ORIGINAL_PS1_WAS_SET=1
        else
            MODERN_BASH_PROMPT_ORIGINAL_PS1_WAS_SET=0
        fi
        MODERN_BASH_PROMPT_ORIGINAL_PS1=${PS1-}
        MODERN_BASH_PROMPT_ORIGINAL_PS1_SET=1
    fi
    if ! modern_bash::prompt::render 0; then
        MODERN_BASH_PROMPT_ERROR='PS1 could not be updated'
        return 1
    fi
    if ! modern_bash::prompt::_install_hook; then
        if [[ ${MODERN_BASH_PROMPT_ORIGINAL_PS1_WAS_SET} == 1 ]]; then
            PS1=${MODERN_BASH_PROMPT_ORIGINAL_PS1}
        else
            unset PS1
        fi
        MODERN_BASH_PROMPT_ERROR=${MODERN_BASH_PROMPT_ERROR:-PROMPT_COMMAND could not be updated}
        modern_bash::prompt::_clear_snapshot
        return 1
    fi
    MODERN_BASH_PROMPT_ENABLED=1
}

MODERN_BASH_PROMPT_LOAD_STATE=(complete)
