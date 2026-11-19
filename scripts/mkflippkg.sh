#!/bin/bash
set -euo pipefail
export LC_ALL=C.UTF-8
DEST=${1:?destdir}
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/kwin-plugin.sh"
kwin_plugin_build "${FLIP_SRC:-$HERE/../src/kwin-flip}" "$DEST"
kwin_plugin_copyright "$DEST" kwick-flip <<'EOF'
kwick_flip KWin effect plugin (Flip: flip, door and tilt open/close animations)

Source: src/kwin-flip in the KwickOS repository.
License of the source: MIT, Copyright (c) 2026 Carsen Klock.

The compiled plugin links against KWin, which is licensed GPL-2.0-or-later,
so the binary kwick_flip.so is distributed under the terms of the
GPL-2.0-or-later. Its MIT source is GPL-compatible and is available in the
KwickOS repository. KWin's license text is in /usr/share/common-licenses/GPL-2.
EOF
find "$DEST/usr" -name 'kwick_flip.so' | head
