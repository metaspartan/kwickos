#!/bin/bash
set -euo pipefail
export LC_ALL=C.UTF-8
DEST=${1:?destdir}
HERE=$(cd "$(dirname "$0")" && pwd)
FLIP=${FLIP_SRC:-$HERE/../src/kwin-flip}
DEPS="build-essential cmake extra-cmake-modules pkg-config kwin-dev libepoxy-dev libwayland-dev qt6-base-dev qt6-base-private-dev qt6-declarative-dev libkf6config-dev libkf6coreaddons-dev libkf6windowsystem-dev libkdecorations3-dev"
if ! dpkg -s kwin-dev qt6-base-private-dev extra-cmake-modules >/dev/null 2>&1; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $DEPS
fi
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cmake -S "$FLIP" -B "$W/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=OFF >/dev/null
cmake --build "$W/build" -j"$(nproc)" >/dev/null
DESTDIR="$DEST" cmake --install "$W/build" >/dev/null
mkdir -p "$DEST/usr/share/doc/kwick-flip"
cat > "$DEST/usr/share/doc/kwick-flip/copyright" <<'EOF'
kwick_flip KWin effect plugin (Flip: flip, door and tilt open/close animations)

Source: src/kwin-flip in the KwickOS repository.
License of the source: MIT, Copyright (c) 2026 Carsen Klock.

The compiled plugin links against KWin, which is licensed GPL-2.0-or-later,
so the binary kwick_flip.so is distributed under the terms of the
GPL-2.0-or-later. Its MIT source is GPL-compatible and is available in the
KwickOS repository. KWin's license text is in /usr/share/common-licenses/GPL-2.
EOF
find "$DEST/usr" -name 'kwick_flip.so' | head
