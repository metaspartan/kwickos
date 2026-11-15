#!/bin/bash
set -euo pipefail
export LC_ALL=C.UTF-8
DEST=${1:?destdir}
HERE=$(cd "$(dirname "$0")" && pwd)
STYLE=${STYLE_SRC:-$HERE/../src/kwick-macstyle}
DEPS="build-essential cmake extra-cmake-modules pkg-config kwin-dev libepoxy-dev libwayland-dev qt6-base-dev qt6-base-private-dev qt6-declarative-dev libkf6config-dev libkf6coreaddons-dev libkf6windowsystem-dev libkdecorations3-dev"
if ! dpkg -s kwin-dev qt6-base-private-dev extra-cmake-modules >/dev/null 2>&1; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $DEPS
fi
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cmake -S "$STYLE" -B "$W/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=OFF >/dev/null
cmake --build "$W/build" -j"$(nproc)" >/dev/null
DESTDIR="$DEST" cmake --install "$W/build" >/dev/null
mkdir -p "$DEST/usr/share/doc/kwick-macstyle"
cat > "$DEST/usr/share/doc/kwick-macstyle/copyright" <<'EOF'
kwickmac Qt widget style (Breeze with macOS Tahoe menus) for the KwickOS macOS layout

Source: src/kwick-macstyle in the KwickOS repository.
License of the source: MIT, Copyright (c) 2026 Carsen Klock.

The compiled plugin loads the Breeze style at run time and links against Qt.
EOF
find "$DEST/usr" -name 'kwickmac.so' | head
