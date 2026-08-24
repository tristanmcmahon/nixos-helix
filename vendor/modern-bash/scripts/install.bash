#!/usr/bin/env bash

set -o nounset
set -o pipefail

# Inherited interactive options must not block managed-file replacement, make
# installer globs fatal, or alter how empty directories are inspected.
set +o noclobber
shopt -u failglob nullglob

modern_bash_install_runtime_executables=(
    bin/modern-bash
)
modern_bash_install_runtime_files=(
    scripts/install.bash
    src/modern-bash.bash
    src/init.bash
    src/lib/capabilities.bash
    src/lib/theme.bash
    src/lib/output.bash
    src/lib/config.bash
    src/lib/bootstrap.bash
    src/features/prompt.bash
    src/commands/doctor.bash
)
modern_bash_install_runtime_directories=(
    bin
    scripts
    src
    src/lib
    src/features
    src/commands
)
modern_bash_install_documentation_files=(
    README.md
    CHANGELOG.md
    CONTRIBUTING.md
    docs/configuration.md
    docs/engineering-principles.md
)
modern_bash_install_documentation_directories=(
    docs
)

modern_bash::install::usage() {
    cat <<'USAGE'
Usage: scripts/install.bash <install|uninstall> [options]

Install or remove the Modern Bash runtime. Configuration and shell startup
files are never modified.

Options:
  --prefix PATH    Runtime prefix (default: $HOME/.local)
  --destdir PATH   Staging root for packaging (default: empty)
  -h, --help       Show this help

The installed layout is:
  PREFIX/bin/modern-bash -> ../lib/modern-bash/bin/modern-bash
  PREFIX/lib/modern-bash/...
  PREFIX/share/doc/modern-bash/...
USAGE
}

modern_bash::install::error() {
    local message=$*

    message=${message//[[:cntrl:]]/?}
    printf 'modern-bash installer: %s\n' "${message}" >&2
}

modern_bash::install::normalize_paths() {
    while [[ ${modern_bash_install_prefix} != / && ${modern_bash_install_prefix} == */ ]]; do
        modern_bash_install_prefix=${modern_bash_install_prefix%/}
    done
    while [[ ${modern_bash_install_destdir} != / && ${modern_bash_install_destdir} == */ ]]; do
        modern_bash_install_destdir=${modern_bash_install_destdir%/}
    done
    if [[ ${modern_bash_install_destdir} == / ]]; then
        modern_bash_install_destdir=''
    fi

    case ${modern_bash_install_prefix} in
        /*) ;;
        *)
            modern_bash::install::error '--prefix must be an absolute path'
            return 64
            ;;
    esac
    case ${modern_bash_install_destdir} in
        ''|/*) ;;
        *)
            modern_bash::install::error '--destdir must be empty or an absolute path'
            return 64
            ;;
    esac

    case /${modern_bash_install_prefix#/}/ in
        */../*|*/./*)
            modern_bash::install::error '--prefix must not contain . or .. path components'
            return 64
            ;;
    esac
    if [[ -n ${modern_bash_install_destdir} ]]; then
        case /${modern_bash_install_destdir#/}/ in
            */../*|*/./*)
                modern_bash::install::error '--destdir must not contain . or .. path components'
                return 64
                ;;
        esac
    fi

    modern_bash::install::set_staged_paths "${modern_bash_install_destdir}"
    modern_bash_install_display_staged_prefix=${modern_bash_install_staged_prefix}
}

modern_bash::install::set_staged_paths() {
    local staging_root=$1

    if [[ ${modern_bash_install_prefix} == / ]]; then
        modern_bash_install_staged_prefix=${staging_root:-/}
    else
        modern_bash_install_staged_prefix=${staging_root}${modern_bash_install_prefix}
    fi
    modern_bash_install_runtime_root=${modern_bash_install_staged_prefix}/lib/modern-bash
    modern_bash_install_doc_root=${modern_bash_install_staged_prefix}/share/doc/modern-bash
    modern_bash_install_launcher=${modern_bash_install_staged_prefix}/bin/modern-bash
    modern_bash_install_link_target='../lib/modern-bash/bin/modern-bash'
    modern_bash_install_marker=${modern_bash_install_runtime_root}/.modern-bash-install
    modern_bash_install_doc_marker=${modern_bash_install_doc_root}/.modern-bash-install
}

modern_bash::install::validate_staged_prefix_components() {
    local component=''
    local component_path=${modern_bash_install_destdir_real}
    local remaining=${modern_bash_install_prefix#/}

    while [[ -n ${remaining} ]]; do
        case ${remaining} in
            */*)
                component=${remaining%%/*}
                remaining=${remaining#*/}
                ;;
            *)
                component=${remaining}
                remaining=''
                ;;
        esac
        [[ -n ${component} ]] || continue
        component_path=${component_path%/}/${component}
        modern_bash::install::validate_directory "${component_path}" || return
    done
}

modern_bash::install::prepare_destdir() {
    local operation=$1

    [[ -n ${modern_bash_install_destdir} ]] || return 0

    if [[ -h ${modern_bash_install_destdir} && ! -d ${modern_bash_install_destdir} ]]; then
        modern_bash::install::error \
            "refusing to use a dangling staging-root symlink: ${modern_bash_install_destdir}"
        return 1
    fi
    if [[ -e ${modern_bash_install_destdir} && ! -d ${modern_bash_install_destdir} ]]; then
        modern_bash::install::error \
            "refusing to use a non-directory staging root: ${modern_bash_install_destdir}"
        return 1
    fi
    if [[ ! -d ${modern_bash_install_destdir} ]]; then
        if [[ ${operation} == remove ]]; then
            return 0
        fi
        command install -d -m 0755 "${modern_bash_install_destdir}" || return
    fi

    modern_bash_install_destdir_real=$(
        CDPATH='' builtin cd -- "${modern_bash_install_destdir}" && builtin pwd -P
    ) || {
        modern_bash::install::error \
            "cannot resolve staging root: ${modern_bash_install_destdir}"
        return 1
    }
    modern_bash::install::set_staged_paths "${modern_bash_install_destdir_real}"
    modern_bash::install::validate_staged_prefix_components
}

modern_bash::install::launcher_is_ours() {
    local target=''

    [[ -h ${modern_bash_install_launcher} ]] || return 1
    target=$(command readlink "${modern_bash_install_launcher}" 2>/dev/null) || return 1
    [[ ${target} == "${modern_bash_install_link_target}" ]]
}

modern_bash::install::marker_is_valid() {
    local marker_value=''

    [[ ! -h ${modern_bash_install_marker} && -f ${modern_bash_install_marker} &&
        -r ${modern_bash_install_marker} ]] || return 1
    IFS= read -r marker_value <"${modern_bash_install_marker}" || return 1
    [[ ${marker_value} == 'modern-bash:user-install:v1' ]]
}

modern_bash::install::doc_marker_is_valid() {
    local marker_value=''

    [[ ! -h ${modern_bash_install_doc_marker} && -f ${modern_bash_install_doc_marker} &&
        -r ${modern_bash_install_doc_marker} ]] || return 1
    IFS= read -r marker_value <"${modern_bash_install_doc_marker}" || return 1
    [[ ${marker_value} == 'modern-bash:user-install:v1' ]]
}

modern_bash::install::source_is_managed_runtime() {
    local marker_path=${modern_bash_install_project_root}/.modern-bash-install
    local marker_value=''

    [[ ! -h ${marker_path} && -f ${marker_path} && -r ${marker_path} ]] || return 1
    IFS= read -r marker_value <"${marker_path}" || return 1
    [[ ${marker_value} == 'modern-bash:user-install:v1' ]]
}

modern_bash::install::validate_directory() {
    local directory_path=$1

    if [[ -h ${directory_path} ]]; then
        modern_bash::install::error \
            "refusing to follow a directory symlink: ${directory_path}"
        return 1
    fi
    if [[ -e ${directory_path} && ! -d ${directory_path} ]]; then
        modern_bash::install::error \
            "refusing to use a non-directory path: ${directory_path}"
        return 1
    fi
}

modern_bash::install::validate_managed_directories() {
    local directory_path=''
    local relative_path=''

    for directory_path in \
        "${modern_bash_install_staged_prefix}" \
        "${modern_bash_install_staged_prefix}/bin" \
        "${modern_bash_install_staged_prefix}/lib" \
        "${modern_bash_install_runtime_root}" \
        "${modern_bash_install_staged_prefix}/share" \
        "${modern_bash_install_staged_prefix}/share/doc" \
        "${modern_bash_install_doc_root}"; do
        modern_bash::install::validate_directory "${directory_path}" || return
    done
    for relative_path in "${modern_bash_install_runtime_directories[@]}"; do
        modern_bash::install::validate_directory \
            "${modern_bash_install_runtime_root}/${relative_path}" || return
    done
    for relative_path in "${modern_bash_install_documentation_directories[@]}"; do
        modern_bash::install::validate_directory \
            "${modern_bash_install_doc_root}/${relative_path}" || return
    done
}

modern_bash::install::validate_managed_file() {
    local file_path=$1
    local operation=$2

    if [[ -h ${file_path} || (-e ${file_path} && ! -f ${file_path}) ]]; then
        modern_bash::install::error \
            "refusing to ${operation} an unsafe managed path: ${file_path}"
        return 1
    fi
}

modern_bash::install::validate_managed_files() {
    local operation=$1
    local relative_path=''

    for relative_path in \
        "${modern_bash_install_runtime_executables[@]}" \
        "${modern_bash_install_runtime_files[@]}"; do
        modern_bash::install::validate_managed_file \
            "${modern_bash_install_runtime_root}/${relative_path}" "${operation}" || return
    done
    for relative_path in "${modern_bash_install_documentation_files[@]}"; do
        modern_bash::install::validate_managed_file \
            "${modern_bash_install_doc_root}/${relative_path}" "${operation}" || return
    done
}

modern_bash::install::preflight() {
    local operation=$1

    modern_bash::install::validate_managed_directories || return
    if [[ -e ${modern_bash_install_launcher} || -h ${modern_bash_install_launcher} ]]; then
        if ! modern_bash::install::launcher_is_ours; then
            modern_bash::install::error \
                "refusing to ${operation} an unmanaged path: ${modern_bash_install_launcher}"
            return 1
        fi
    fi
    if [[ -e ${modern_bash_install_runtime_root} ]] && \
        ! modern_bash::install::marker_is_valid; then
        modern_bash::install::error \
            "refusing to ${operation} an unmanaged runtime: ${modern_bash_install_runtime_root}"
        return 1
    fi
    if [[ -e ${modern_bash_install_doc_root} ]] && \
        ! modern_bash::install::doc_marker_is_valid; then
        modern_bash::install::error \
            "refusing to ${operation} unmanaged documentation: ${modern_bash_install_doc_root}"
        return 1
    fi
    modern_bash::install::validate_managed_files "${operation}"
}

modern_bash::install::ensure_directory() {
    local directory_path=$1

    modern_bash::install::validate_directory "${directory_path}" || return
    if [[ -d ${directory_path} ]]; then
        return 0
    fi
    command install -d -m 0755 "${directory_path}" || return
    modern_bash::install::validate_directory "${directory_path}"
}

modern_bash::install::ensure_staged_prefix() {
    local component=''
    local component_path=${modern_bash_install_destdir_real}
    local remaining=${modern_bash_install_prefix#/}

    while [[ -n ${remaining} ]]; do
        case ${remaining} in
            */*)
                component=${remaining%%/*}
                remaining=${remaining#*/}
                ;;
            *)
                component=${remaining}
                remaining=''
                ;;
        esac
        [[ -n ${component} ]] || continue
        component_path=${component_path%/}/${component}
        modern_bash::install::ensure_directory "${component_path}" || return
    done
}

modern_bash::install::create_directories() {
    local relative_path=''

    if [[ -n ${modern_bash_install_destdir} ]]; then
        modern_bash::install::ensure_staged_prefix || return
    else
        modern_bash::install::ensure_directory "${modern_bash_install_staged_prefix}" || return
    fi
    modern_bash::install::ensure_directory "${modern_bash_install_staged_prefix}/bin" || return
    modern_bash::install::ensure_directory "${modern_bash_install_staged_prefix}/lib" || return
    modern_bash::install::ensure_directory "${modern_bash_install_runtime_root}" || return
    for relative_path in "${modern_bash_install_runtime_directories[@]}"; do
        modern_bash::install::ensure_directory \
            "${modern_bash_install_runtime_root}/${relative_path}" || return
    done
    modern_bash::install::ensure_directory "${modern_bash_install_staged_prefix}/share" || return
    modern_bash::install::ensure_directory "${modern_bash_install_staged_prefix}/share/doc" || return
    modern_bash::install::ensure_directory "${modern_bash_install_doc_root}" || return
    for relative_path in "${modern_bash_install_documentation_directories[@]}"; do
        modern_bash::install::ensure_directory \
            "${modern_bash_install_doc_root}/${relative_path}" || return
    done
}

modern_bash::install::write_marker() {
    local marker_path=$1

    printf '%s\n' 'modern-bash:user-install:v1' >"${marker_path}" || return
    command chmod 0644 "${marker_path}"
}

modern_bash::install::install() {
    local relative_path=''
    local display_prefix=${modern_bash_install_display_staged_prefix//[[:cntrl:]]/?}

    if ! command -v install >/dev/null 2>&1 || \
        ! command -v readlink >/dev/null 2>&1 || \
        ! command -v ln >/dev/null 2>&1 || \
        ! command -v chmod >/dev/null 2>&1; then
        modern_bash::install::error 'install, readlink, ln, and chmod are required'
        return 127
    fi
    if [[ ${modern_bash_install_project_root} != "${modern_bash_install_runtime_root}" ]] && \
        modern_bash::install::source_is_managed_runtime; then
        modern_bash::install::error \
            'installing to a different prefix requires a source checkout'
        return 1
    fi
    modern_bash::install::prepare_destdir replace || return
    if [[ ${modern_bash_install_project_root} == "${modern_bash_install_runtime_root}" ]]; then
        modern_bash::install::preflight replace || return
        printf 'Modern Bash is already installed under %s\n' "${display_prefix}"
        return 0
    fi
    modern_bash::install::preflight replace || return
    for relative_path in \
        "${modern_bash_install_runtime_executables[@]}" \
        "${modern_bash_install_runtime_files[@]}" \
        "${modern_bash_install_documentation_files[@]}"; do
        if [[ ! -f ${modern_bash_install_project_root}/${relative_path} ||
            ! -r ${modern_bash_install_project_root}/${relative_path} ]]; then
            modern_bash::install::error \
                "source package is incomplete: ${modern_bash_install_project_root}/${relative_path}"
            return 1
        fi
    done

    modern_bash::install::create_directories || return
    modern_bash::install::write_marker "${modern_bash_install_marker}" || return
    modern_bash::install::write_marker "${modern_bash_install_doc_marker}" || return

    for relative_path in "${modern_bash_install_runtime_executables[@]}"; do
        command install -m 0755 "${modern_bash_install_project_root}/${relative_path}" \
            "${modern_bash_install_runtime_root}/${relative_path}" || return
    done
    for relative_path in "${modern_bash_install_runtime_files[@]}"; do
        command install -m 0644 "${modern_bash_install_project_root}/${relative_path}" \
            "${modern_bash_install_runtime_root}/${relative_path}" || return
    done
    for relative_path in "${modern_bash_install_documentation_files[@]}"; do
        command install -m 0644 "${modern_bash_install_project_root}/${relative_path}" \
            "${modern_bash_install_doc_root}/${relative_path}" || return
    done
    if [[ ! -h ${modern_bash_install_launcher} ]]; then
        command ln -s "${modern_bash_install_link_target}" \
            "${modern_bash_install_launcher}" || return
    fi

    printf 'Installed Modern Bash under %s\n' "${display_prefix}"
    if [[ -z ${modern_bash_install_destdir} ]]; then
        display_prefix=${modern_bash_install_prefix//[[:cntrl:]]/?}
        printf 'Add %s/bin to PATH, then add this to .bashrc:\n' "${display_prefix}"
        # This is intentionally a literal command for the user to copy.
        # shellcheck disable=SC2016
        printf '%s\n' '  eval "$(modern-bash init)"'
    fi
}

modern_bash::install::runtime_has_unmanaged_files() {
    local candidate=''

    for candidate in \
        "${modern_bash_install_runtime_root}"/* \
        "${modern_bash_install_runtime_root}"/.[!.]* \
        "${modern_bash_install_runtime_root}"/..?*; do
        if [[ ! -e ${candidate} && ! -h ${candidate} ]]; then
            continue
        fi
        if [[ ${candidate} != "${modern_bash_install_marker}" ]]; then
            return 0
        fi
    done
    return 1
}

modern_bash::install::docs_have_unmanaged_files() {
    local candidate=''

    for candidate in \
        "${modern_bash_install_doc_root}"/* \
        "${modern_bash_install_doc_root}"/.[!.]* \
        "${modern_bash_install_doc_root}"/..?*; do
        if [[ ! -e ${candidate} && ! -h ${candidate} ]]; then
            continue
        fi
        if [[ ${candidate} != "${modern_bash_install_doc_marker}" ]]; then
            return 0
        fi
    done
    return 1
}

modern_bash::install::uninstall() {
    local modern_bash_uninstall_status=0
    local display_prefix=${modern_bash_install_display_staged_prefix//[[:cntrl:]]/?}
    local directory_index=0
    local relative_path=''

    if ! command -v readlink >/dev/null 2>&1 || \
        ! command -v rm >/dev/null 2>&1 || \
        ! command -v rmdir >/dev/null 2>&1; then
        modern_bash::install::error 'readlink, rm, and rmdir are required'
        return 127
    fi
    modern_bash::install::prepare_destdir remove || return
    modern_bash::install::preflight remove || return

    if [[ -h ${modern_bash_install_launcher} ]]; then
        command rm -f "${modern_bash_install_launcher}" || return
    fi
    if [[ -d ${modern_bash_install_runtime_root} ]]; then
        for relative_path in \
            "${modern_bash_install_runtime_executables[@]}" \
            "${modern_bash_install_runtime_files[@]}"; do
            command rm -f \
                "${modern_bash_install_runtime_root}/${relative_path}" || return
        done
        directory_index=$((${#modern_bash_install_runtime_directories[@]} - 1))
        while ((directory_index >= 0)); do
            relative_path=${modern_bash_install_runtime_directories[directory_index]}
            command rmdir \
                "${modern_bash_install_runtime_root}/${relative_path}" 2>/dev/null || :
            directory_index=$((directory_index - 1))
        done

        if modern_bash::install::runtime_has_unmanaged_files; then
            modern_bash::install::error \
                "runtime contains unmanaged files and was preserved: ${modern_bash_install_runtime_root}"
            modern_bash_uninstall_status=1
        else
            command rm -f "${modern_bash_install_marker}" || return
            command rmdir "${modern_bash_install_runtime_root}" 2>/dev/null || :
        fi
    fi

    if [[ -d ${modern_bash_install_doc_root} ]]; then
        for relative_path in "${modern_bash_install_documentation_files[@]}"; do
            command rm -f \
                "${modern_bash_install_doc_root}/${relative_path}" || return
        done
        directory_index=$((${#modern_bash_install_documentation_directories[@]} - 1))
        while ((directory_index >= 0)); do
            relative_path=${modern_bash_install_documentation_directories[directory_index]}
            command rmdir \
                "${modern_bash_install_doc_root}/${relative_path}" 2>/dev/null || :
            directory_index=$((directory_index - 1))
        done
        if modern_bash::install::docs_have_unmanaged_files; then
            modern_bash::install::error \
                "documentation contains unmanaged files and was preserved: ${modern_bash_install_doc_root}"
            modern_bash_uninstall_status=1
        else
            command rm -f "${modern_bash_install_doc_marker}" || return
            command rmdir "${modern_bash_install_doc_root}" 2>/dev/null || :
        fi
    fi

    if ((modern_bash_uninstall_status == 0)); then
        printf 'Uninstalled Modern Bash from %s\n' "${display_prefix}"
        printf 'Configuration and shell startup files were left unchanged.\n'
    fi
    return "${modern_bash_uninstall_status}"
}

modern_bash_install_script=${BASH_SOURCE[0]}
case ${modern_bash_install_script} in
    */*) modern_bash_install_script_dir=${modern_bash_install_script%/*} ;;
    *) modern_bash_install_script_dir=. ;;
esac
modern_bash_install_script_dir=$(
    CDPATH='' builtin cd -- "${modern_bash_install_script_dir}" && builtin pwd -P
) || exit 1
modern_bash_install_project_root=$(
    CDPATH='' builtin cd -- "${modern_bash_install_script_dir}/.." && builtin pwd -P
) || exit 1

modern_bash_install_mode=${1:-}
if (($# > 0)); then
    shift
fi
if [[ ${modern_bash_install_mode} == -h || ${modern_bash_install_mode} == --help ]]; then
    modern_bash::install::usage
    exit 0
fi
case ${modern_bash_install_mode} in
    install|uninstall) ;;
    '')
        modern_bash::install::usage >&2
        exit 64
        ;;
    *)
        modern_bash::install::error "unknown operation: ${modern_bash_install_mode}"
        exit 64
        ;;
esac

if [[ ${MODERN_BASH_INSTALL_PREFIX+x} == x ]]; then
    modern_bash_install_prefix=${MODERN_BASH_INSTALL_PREFIX}
    modern_bash_install_prefix_explicit=1
elif [[ -n ${HOME:-} ]]; then
    modern_bash_install_prefix=${HOME}/.local
    modern_bash_install_prefix_explicit=0
else
    modern_bash_install_prefix=''
    modern_bash_install_prefix_explicit=0
fi
modern_bash_install_destdir=${MODERN_BASH_INSTALL_DESTDIR:-}

while (($# > 0)); do
    case $1 in
        --prefix)
            if (($# < 2)); then
                modern_bash::install::error '--prefix requires a path'
                exit 64
            fi
            modern_bash_install_prefix=$2
            modern_bash_install_prefix_explicit=1
            shift 2
            ;;
        --destdir)
            if (($# < 2)); then
                modern_bash::install::error '--destdir requires a path'
                exit 64
            fi
            modern_bash_install_destdir=$2
            shift 2
            ;;
        -h|--help)
            modern_bash::install::usage
            exit 0
            ;;
        *)
            modern_bash::install::error "unknown option: $1"
            exit 64
            ;;
    esac
done

if [[ ${modern_bash_install_prefix_explicit} == 0 &&
    ${modern_bash_install_project_root} == */lib/modern-bash ]]; then
    modern_bash_install_self_marker=''
    if IFS= read -r modern_bash_install_self_marker \
        <"${modern_bash_install_project_root}/.modern-bash-install" 2>/dev/null &&
        [[ ${modern_bash_install_self_marker} == 'modern-bash:user-install:v1' ]]; then
        modern_bash_install_prefix=${modern_bash_install_project_root%/lib/modern-bash}
        if [[ -z ${modern_bash_install_prefix} ]]; then
            modern_bash_install_prefix=/
        fi
    fi
    unset modern_bash_install_self_marker
fi
if [[ -z ${modern_bash_install_prefix} ]]; then
    modern_bash::install::error 'HOME is unset; pass --prefix explicitly'
    exit 64
fi

modern_bash::install::normalize_paths || exit
case ${modern_bash_install_mode} in
    install) modern_bash::install::install ;;
    uninstall) modern_bash::install::uninstall ;;
esac
