#!/bin/bash
set -euo pipefail
export LC_ALL=C.UTF-8
DEST=${1:?destdir}
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/kwin-plugin.sh"
kwin_plugin_build "${GLASS_SRC:-$HERE/../src/kwin-liquidglass}" "$DEST"
kwin_plugin_copyright "$DEST" kwick-liquidglass <<'EOF'
kwick_liquidglass KWin effect plugin (Liquid Glass: refracting, frosted glass
for the dock, menu bar, menus, popups, notifications and OSDs)

Source: src/kwin-liquidglass in the KwickOS repository.
License of the source: MIT, Copyright (c) 2026 Carsen Klock.

The compiled plugin links against KWin, which is licensed GPL-2.0-or-later,
so the binary kwick_liquidglass.so is distributed under the terms of the
GPL-2.0-or-later. Its MIT source is GPL-compatible and is available in the
KwickOS repository. KWin's license text is in /usr/share/common-licenses/GPL-2.
EOF
find "$DEST/usr" -name 'kwick_liquidglass.so' | head
