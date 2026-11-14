#!/usr/bin/env bash
set -euo pipefail

package_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
plugin_id=org.alienrobot.hamstatus
package_type=Plasma/Applet

usage() {
    cat <<EOF
Usage: ${0##*/} [validate|install|remove|status]

validate  check metadata/config structure without changing Plasma
install   install or upgrade the user-local Plasma 6 widget
remove    remove the user-local widget
status    show installed package metadata
EOF
}

validate() {
    python3 - "$package_dir" <<'PY'
import json
import pathlib
import sys
import xml.etree.ElementTree as ET

root = pathlib.Path(sys.argv[1])
metadata = json.loads((root / "metadata.json").read_text(encoding="utf-8"))
assert metadata["KPackageStructure"] == "Plasma/Applet"
assert metadata["X-Plasma-API-Minimum-Version"] == "6.0"
assert metadata["KPlugin"]["Id"] == "org.alienrobot.hamstatus"
ET.parse(root / "contents/config/main.xml")
for relative in (
    "contents/config/config.qml",
    "contents/ui/configGeneral.qml",
    "contents/ui/main.qml",
):
    path = root / relative
    assert path.is_file() and path.stat().st_size > 0, relative
print("PASS  plasmoid structure and metadata")
PY

    if command -v qmllint >/dev/null 2>&1; then
        qmllint "$package_dir/contents/ui/main.qml" \
                "$package_dir/contents/ui/configGeneral.qml" \
                "$package_dir/contents/config/config.qml"
        echo "PASS  qmllint"
    else
        echo "INFO  qmllint not installed; skipped QML lint"
    fi
}

install_widget() {
    command -v kpackagetool6 >/dev/null 2>&1 || {
        echo "error: kpackagetool6 is required" >&2
        exit 1
    }
    validate
    if kpackagetool6 --type "$package_type" --show "$plugin_id" >/dev/null 2>&1; then
        kpackagetool6 --type "$package_type" --upgrade "$package_dir"
    else
        kpackagetool6 --type "$package_type" --install "$package_dir"
    fi
    echo
    echo "Installed $plugin_id."
    echo "Add 'alienrobot Service Health' to a Plasma panel from Edit Mode."
}

case "${1:-validate}" in
    validate)
        validate
        ;;
    install)
        install_widget
        ;;
    remove)
        command -v kpackagetool6 >/dev/null 2>&1 || {
            echo "error: kpackagetool6 is required" >&2
            exit 1
        }
        kpackagetool6 --type "$package_type" --remove "$plugin_id"
        ;;
    status)
        command -v kpackagetool6 >/dev/null 2>&1 || {
            echo "error: kpackagetool6 is required" >&2
            exit 1
        }
        kpackagetool6 --type "$package_type" --show "$plugin_id"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
