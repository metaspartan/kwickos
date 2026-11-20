#!/bin/bash
set -euo pipefail
export LC_ALL=C.UTF-8
DEST=${1:?destdir}
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/kwin-plugin.sh"
kwin_plugin_build "${STYLE_SRC:-$HERE/../src/kwick-macstyle}" "$DEST"
kwin_plugin_copyright "$DEST" kwick-macstyle <<'EOF'
kwickmac Qt widget style (Breeze with macOS Tahoe or Windows 11 menus) for the KwickOS macOS and Windows layouts

Source: src/kwick-macstyle in the KwickOS repository.
License of the source: MIT, Copyright (c) 2026 Carsen Klock.

The compiled plugin loads the Breeze style at run time and links against Qt.
EOF
find "$DEST/usr" -name 'kwickmac.so' | head
