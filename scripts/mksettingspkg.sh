#!/bin/bash
set -euo pipefail
export LC_ALL=C.UTF-8
DEST=${1:?destdir}
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/kwin-plugin.sh"
kwin_plugin_build "${SETTINGS_SRC:-$HERE/../src/kwick-settings}" "$DEST"
kwin_plugin_copyright "$DEST" kwick-settings <<'EOF'
kwick-settings-app, the launcher of the KwickOS Settings app: it loads
/usr/share/kwick/settings/Main.qml with the desktop file name kwick-settings,
so window switchers, the dock and the task bar show the Settings icon

Source: src/kwick-settings in the KwickOS repository.
License of the source: MIT, Copyright (c) 2026 Carsen Klock.

The binary links against Qt.
EOF
find "$DEST/usr" -name 'kwick-settings-app' | head
