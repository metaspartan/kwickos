#!/bin/bash
set -euo pipefail
export LC_ALL=C.UTF-8
DEST=${1:?destdir}
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${NATIVE_SRC:-$HERE/../src}
DEPS="build-essential cmake extra-cmake-modules pkg-config qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-svg-dev libkf6config-dev libkf6coreaddons-dev libkf6dbusaddons-dev libkf6kio-dev liblayershellqtinterface-dev libpoppler-qt6-dev libarchive-dev"
if ! dpkg -s $DEPS >/dev/null 2>&1; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $DEPS
fi
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
for app in kwick-quicklook kwick-capture; do
  cmake -S "$SRC/$app" -B "$W/$app" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -Wno-dev >/dev/null
  cmake --build "$W/$app" -j"$(nproc)" >/dev/null
  DESTDIR="$DEST" cmake --install "$W/$app" --strip >/dev/null
done
mkdir -p "$DEST/usr/share/kglobalaccel"
ln -sf ../applications/kwick-capture.desktop "$DEST/usr/share/kglobalaccel/kwick-capture.desktop"
mkdir -p "$DEST/usr/share/doc/kwick-native"
cat > "$DEST/usr/share/doc/kwick-native/copyright" <<'COPYRIGHT'
kwick-quicklook (Quick Look previews for Files, Nautilus and Spotlight, with a Dolphin
Space-key hook) and kwick-capture (screenshots, screen recording, markup, text
recognition and color picking)

Source: src/kwick-quicklook and src/kwick-capture in the KwickOS repository.
License of the source: MIT, Copyright (c) 2026 Carsen Klock.

The binaries link against Qt, KDE Frameworks (KConfig, KCoreAddons, KIO,
KDBusAddons), LayerShellQt, Poppler and libarchive.
COPYRIGHT
find "$DEST/usr" -type f \( -name kwick-quicklook -o -name kwick-capture -o -name 'kwick_quicklook_dolphin.so' \)
