#!/usr/bin/env bash

# This is the interactive entry point intended for .bashrc. Scripts may source
# it safely: no files are loaded and no state is changed outside an interactive
# shell.
case $- in
    *i*) ;;
    *) return 0 ;;
esac

modern_bash_init_path=${BASH_SOURCE[0]}
case ${modern_bash_init_path} in
    */*) modern_bash_init_dir=${modern_bash_init_path%/*} ;;
    *) modern_bash_init_dir=. ;;
esac
modern_bash_init_dir=$(CDPATH='' builtin cd -- "${modern_bash_init_dir}" && builtin pwd -P) || {
    unset modern_bash_init_path modern_bash_init_dir
    return 1
}
unset modern_bash_init_path

# shellcheck source=src/modern-bash.bash
builtin source "${modern_bash_init_dir}/modern-bash.bash" || {
    unset modern_bash_init_dir
    return 1
}
unset modern_bash_init_dir

if ! modern_bash::bootstrap::initialize; then
    modern_bash_init_safe_error=${MODERN_BASH_INIT_ERROR:-unknown error}
    modern_bash_init_safe_error=${modern_bash_init_safe_error//[[:cntrl:]]/?}
    printf 'modern-bash: initialization failed: %s\n' \
        "${modern_bash_init_safe_error}" >&2
    unset modern_bash_init_safe_error
    return 1
fi
