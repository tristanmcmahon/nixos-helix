#!/usr/bin/env bash

# This file is a sourceable entry point. It intentionally does not alter shell
# options, traps, aliases, the working directory, or the caller's IFS.

modern_bash_loader_path=${BASH_SOURCE[0]}
case ${modern_bash_loader_path} in
    */*) modern_bash_loader_dir=${modern_bash_loader_path%/*} ;;
    *) modern_bash_loader_dir=. ;;
esac
modern_bash_loader_dir=$(CDPATH='' builtin cd -- "${modern_bash_loader_dir}" && builtin pwd -P) || {
    unset modern_bash_loader_path modern_bash_loader_dir
    return 1
}
modern_bash_loader_state_declaration=''
modern_bash_loader_prior_runtime_trusted=0
MODERN_BASH_RUNTIME_ERROR=''

modern_bash::runtime::_api_complete() {
    local modern_bash_runtime_required_function=''
    local modern_bash_runtime_required_functions=(
        modern_bash::capabilities::detect
        modern_bash::capabilities::color_name
        modern_bash::theme::init
        modern_bash::output::configure
        modern_bash::output::heading
        modern_bash::output::line
        modern_bash::output::info
        modern_bash::output::success
        modern_bash::output::warning
        modern_bash::output::error
        modern_bash::output::debug
        modern_bash::output::print
        modern_bash::config::resolve
        modern_bash::config::load
        modern_bash::config::apply_defaults
        modern_bash::config::validate
        modern_bash::prompt::render
        modern_bash::prompt::enable
        modern_bash::prompt::disable
        modern_bash::bootstrap::feature_enabled
        modern_bash::bootstrap::validate_features
        modern_bash::bootstrap::initialize
        modern_bash::bootstrap::shutdown
    )

    if [[ ${MODERN_BASH_CAPABILITIES_LOAD_STATE[0]-} != complete ||
        ${MODERN_BASH_THEME_LOAD_STATE[0]-} != complete ||
        ${MODERN_BASH_OUTPUT_LOAD_STATE[0]-} != complete ||
        ${MODERN_BASH_CONFIG_LOAD_STATE[0]-} != complete ||
        ${MODERN_BASH_PROMPT_LOAD_STATE[0]-} != complete ||
        ${MODERN_BASH_BOOTSTRAP_LOAD_STATE[0]-} != complete ]]; then
        return 1
    fi
    for modern_bash_runtime_required_function in \
        "${modern_bash_runtime_required_functions[@]}"; do
        if ! declare -F "${modern_bash_runtime_required_function}" >/dev/null; then
            return 1
        fi
    done
}

if modern_bash_loader_state_declaration=$(declare -p MODERN_BASH_RUNTIME_LOAD_STATE 2>/dev/null) &&
    [[ ${modern_bash_loader_state_declaration} == declare\ -a\ * ]] &&
    [[ ${MODERN_BASH_RUNTIME_LOAD_STATE[0]-} == /* ]] &&
    [[ -n ${MODERN_BASH_RUNTIME_LOAD_STATE[1]-} ]] &&
    [[ ${MODERN_BASH_LOADED:-0} == 1 ]] &&
    declare -F modern_bash::bootstrap::shutdown >/dev/null &&
    declare -F modern_bash::prompt::disable >/dev/null &&
    declare -F modern_bash::prompt::_hook_is_owned >/dev/null; then
    modern_bash_loader_prior_runtime_trusted=1
fi

if [[ ${modern_bash_loader_prior_runtime_trusted} == 1 ]] &&
    [[ ${MODERN_BASH_RUNTIME_LOAD_STATE[0]-} == "${modern_bash_loader_dir}" ]] &&
    [[ ${MODERN_BASH_RUNTIME_LOAD_STATE[1]-} == 0.3.0 ]] &&
    modern_bash::runtime::_api_complete; then
    MODERN_BASH_SOURCE_DIR=${modern_bash_loader_dir}
    unset modern_bash_loader_path modern_bash_loader_dir \
        modern_bash_loader_state_declaration \
        modern_bash_loader_prior_runtime_trusted
    return 0
fi

# A different runtime root or version must not wrap an already active prompt a
# second time. A runtime marker created as an indexed array cannot cross an
# environment boundary, so it is safe evidence that the shutdown functions are
# from a runtime loaded in this shell. Shutdown itself verifies hook ownership
# before changing PROMPT_COMMAND. If that proof is absent, leave the old prompt
# intact and fail closed instead of discarding the only restoration snapshot.
if [[ ${MODERN_BASH_PROMPT_ENABLED:-0} == 1 ]]; then
    if [[ ${modern_bash_loader_prior_runtime_trusted} != 1 ]]; then
        MODERN_BASH_RUNTIME_ERROR='an active unverified Modern Bash prompt must be shut down before loading another runtime'
        unset modern_bash_loader_path modern_bash_loader_dir \
            modern_bash_loader_state_declaration \
            modern_bash_loader_prior_runtime_trusted
        return 1
    fi
fi
if [[ ${modern_bash_loader_prior_runtime_trusted} == 1 ]] &&
    [[ ${MODERN_BASH_INITIALIZED:-0} == 1 || ${MODERN_BASH_PROMPT_ENABLED:-0} == 1 ]]; then
    if ! modern_bash::bootstrap::shutdown; then
        MODERN_BASH_RUNTIME_ERROR=${MODERN_BASH_INIT_ERROR:-the active Modern Bash runtime could not be shut down safely}
        unset modern_bash_loader_path modern_bash_loader_dir \
            modern_bash_loader_state_declaration \
            modern_bash_loader_prior_runtime_trusted
        return 1
    fi
fi

unset modern_bash_loader_path modern_bash_loader_state_declaration \
    modern_bash_loader_prior_runtime_trusted MODERN_BASH_RUNTIME_LOAD_STATE
MODERN_BASH_LOADED=0
MODERN_BASH_VERSION=0.3.0
MODERN_BASH_SOURCE_DIR=${modern_bash_loader_dir}
unset modern_bash_loader_dir

# An inherited scalar flag or exported function is not evidence that a module
# ran to completion in this shell. Reset all module completion markers before
# building one coherent runtime graph.
unset MODERN_BASH_CAPABILITIES_LOADED MODERN_BASH_CAPABILITIES_LOAD_STATE \
    MODERN_BASH_THEME_LOADED MODERN_BASH_THEME_LOAD_STATE \
    MODERN_BASH_OUTPUT_LOADED MODERN_BASH_OUTPUT_LOAD_STATE \
    MODERN_BASH_CONFIG_LOADER_LOADED MODERN_BASH_CONFIG_LOAD_STATE \
    MODERN_BASH_PROMPT_LOADED MODERN_BASH_PROMPT_LOAD_STATE \
    MODERN_BASH_BOOTSTRAP_LOADED MODERN_BASH_BOOTSTRAP_LOAD_STATE

# shellcheck source=src/lib/capabilities.bash
builtin source "${MODERN_BASH_SOURCE_DIR}/lib/capabilities.bash" || return 1
# shellcheck source=src/lib/theme.bash
builtin source "${MODERN_BASH_SOURCE_DIR}/lib/theme.bash" || return 1
# shellcheck source=src/lib/output.bash
builtin source "${MODERN_BASH_SOURCE_DIR}/lib/output.bash" || return 1
# shellcheck source=src/lib/config.bash
builtin source "${MODERN_BASH_SOURCE_DIR}/lib/config.bash" || return 1
# shellcheck source=src/features/prompt.bash
builtin source "${MODERN_BASH_SOURCE_DIR}/features/prompt.bash" || return 1
# shellcheck source=src/lib/bootstrap.bash
builtin source "${MODERN_BASH_SOURCE_DIR}/lib/bootstrap.bash" || return 1

if ! modern_bash::runtime::_api_complete; then
    return 1
fi

unset MODERN_BASH_RUNTIME_LOAD_STATE
MODERN_BASH_RUNTIME_LOAD_STATE=("${MODERN_BASH_SOURCE_DIR}" "${MODERN_BASH_VERSION}")
MODERN_BASH_LOADED=1
