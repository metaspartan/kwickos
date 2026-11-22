#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}; SRC=${SRC:-/src}; OUT=${OUT:-/out}
VER=$(tr -d '\r\n' < "$SRC/VERSION")
QS=${QUICKSHELL_VERSION:-0.3.2}
QS_SHA256=${QUICKSHELL_SHA256:-946a27e2a276917a03c1079e5c60971af84ece73088c3661dee455d92eb420f7}
JOBS=${JOBS:-4}
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends ca-certificates curl cmake ninja-build pkg-config g++ dpkg-dev \
  qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-declarative-private-dev qt6-wayland-dev qt6-wayland-private-dev \
  qt6-shadertools-dev qt6-svg-dev spirv-tools libcli11-dev libwayland-dev wayland-protocols libpipewire-0.3-dev libpam0g-dev \
  libpolkit-agent-1-dev libpolkit-gobject-1-dev libglib2.0-dev libdrm-dev libgbm-dev libjemalloc-dev libegl-dev libgles-dev \
  libvulkan-dev libxcb1-dev >/dev/null
W=$(mktemp -d); cd "$W"
WP=${WAYLAND_PROTOCOLS_VERSION:-1.47}
WP_SHA256=${WAYLAND_PROTOCOLS_SHA256:-5fd4349bcbc9bab9a46f8cf77d1f434296a7a052c87440a094f63fcf62a58e20}
apt-get install -y --no-install-recommends meson xz-utils >/dev/null
curl -fsSL -o wp.tar.xz "https://gitlab.freedesktop.org/wayland/wayland-protocols/-/releases/$WP/downloads/wayland-protocols-$WP.tar.xz"
echo "$WP_SHA256  wp.tar.xz" | sha256sum -c -
mkdir wp && tar xJf wp.tar.xz -C wp --strip-components=1
meson setup wp/build wp --prefix=/usr/local -Dtests=false >/dev/null
meson install -C wp/build >/dev/null
export PKG_CONFIG_PATH=/usr/local/share/pkgconfig
curl -fsSL -o qs.tar.gz "https://github.com/quickshell-mirror/quickshell/archive/refs/tags/v$QS.tar.gz"
echo "$QS_SHA256  qs.tar.gz" | sha256sum -c -
mkdir src && tar xzf qs.tar.gz -C src --strip-components=1
cmake -S src -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr -DDISTRIBUTOR="KwickOS (kwick-quickshell)" \
  -DCRASH_HANDLER=OFF -DSERVICE_GREETD=OFF -DNO_PCH=ON -DINSTALL_QML_PREFIX="lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH)/qt6/qml"
cmake --build build -j"$JOBS"
P=$W/pkg; DESTDIR=$P cmake --install build
find "$P/usr/bin" -type f -exec strip --strip-debug {} + 2>/dev/null || true
mkdir -p "$P/usr/share/doc/kwick-quickshell"
cp src/LICENSE "$P/usr/share/doc/kwick-quickshell/copyright"
mkdir -p debian && echo "Source: kwick-quickshell" > debian/control
deps=$(dpkg-shlibdeps -O --ignore-missing-info "$P/usr/bin/quickshell" 2>/dev/null | sed -n 's/^shlibs:Depends=//p')
mkdir -p "$P/DEBIAN"
cat > "$P/DEBIAN/control" <<EOF
Package: kwick-quickshell
Version: $VER
Architecture: $ARCH
Maintainer: KwickOS Developers <dev@kwickos.org>
Section: x11
Priority: optional
Depends: $deps, qt6-svg-plugins, qml6-module-qtquick, qml6-module-qtquick-controls, qml6-module-qtquick-layouts, qml6-module-qtquick-window, qml6-module-qtqml-workerscript, qml6-module-qtquick-templates, qml6-module-qt5compat-graphicaleffects, qml6-module-qtquick-effects, qml6-module-qtquick-shapes, qml6-module-qtmultimedia
Conflicts: quickshell
Provides: quickshell (= $QS)
Description: Quickshell $QS QML desktop shell toolkit for KwickOS
 Quickshell (LGPL-3.0) built from the pinned v$QS release for Debian 13's Qt.
 It runs Quickshell-based desktop shells such as Dux Shell on Hyprland.
EOF
mkdir -p "$OUT/repo/pool/main"
dpkg-deb --root-owner-group -Zxz -b "$P" "$OUT/repo/pool/main/kwick-quickshell_${VER}_${ARCH}.deb" >/dev/null
echo "packaged kwick-quickshell $VER (Quickshell $QS)"
