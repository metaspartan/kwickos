#!/bin/bash
set -euo pipefail
DEST=${1:?destdir}
VER=0.7.2
SHA256=0a58fa41a9bb5e4ac33ddbe50973138d7189cb3393aa718cd83792b047c2e4f0
URL=https://github.com/matinlotfali/KDE-Rounded-Corners/archive/refs/tags/v$VER.tar.gz
DEPS="build-essential cmake extra-cmake-modules pkg-config curl ca-certificates kwin-dev libepoxy-dev libxcb1-dev qt6-base-dev qt6-base-private-dev libkf6configwidgets-dev libkf6i18n-dev libkf6kcmutils-dev libkf6windowsystem-dev libkf6coreaddons-dev libkdecorations3-dev gettext"
if ! dpkg -s kwin-dev >/dev/null 2>&1; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $DEPS
fi
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
curl -fsSL -o "$W/src.tgz" "$URL"
echo "$SHA256  $W/src.tgz" | sha256sum -c - >/dev/null
tar xzf "$W/src.tgz" -C "$W"
cmake -S "$W/KDE-Rounded-Corners-$VER" -B "$W/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DQT_MAJOR_VERSION=6 -DBUILD_TESTING=OFF >/dev/null
cmake --build "$W/build" -j"$(nproc)" >/dev/null
DESTDIR="$DEST" cmake --install "$W/build" >/dev/null
find "$DEST/usr" -name 'kwin4_effect_shapecorners*' | head
