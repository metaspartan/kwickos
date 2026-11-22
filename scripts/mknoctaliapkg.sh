#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}; SRC=${SRC:-/src}; OUT=${OUT:-/out}
VER=$(tr -d '\r\n' < "$SRC/VERSION")
NOC=${NOCTALIA_VERSION:-5.6.0}
NOC_SHA256=${NOCTALIA_SHA256:-13389cfe443dcb1c0af351b0826df762b08cccabeeea9d6daf7ed1bfb2e7c855}
JOBS=${JOBS:-4}
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends ca-certificates curl meson ninja-build pkg-config g++ dpkg-dev \
  libwayland-dev wayland-protocols libegl-dev libgles-dev libfreetype-dev libfontconfig-dev libcairo2-dev libpango1.0-dev \
  libharfbuzz-dev libxkbcommon-dev libglib2.0-dev libsecret-1-dev libsodium-dev libsdbus-c++-dev libpipewire-0.3-dev \
  libwireplumber-0.5-dev libpam0g-dev libpolkit-agent-1-dev libpolkit-gobject-1-dev libcurl4-gnutls-dev libwebp-dev libjxl-dev \
  libsndfile1-dev librsvg2-dev libqalculate-dev libxml2-dev libmd4c-dev libtomlplusplus-dev libical-dev nlohmann-json3-dev \
  libstb-dev libjemalloc-dev >/dev/null
W=$(mktemp -d); cd "$W"
WP=${WAYLAND_PROTOCOLS_VERSION:-1.47}
WP_SHA256=${WAYLAND_PROTOCOLS_SHA256:-5fd4349bcbc9bab9a46f8cf77d1f434296a7a052c87440a094f63fcf62a58e20}
apt-get install -y --no-install-recommends xz-utils >/dev/null
curl -fsSL -o wp.tar.xz "https://gitlab.freedesktop.org/wayland/wayland-protocols/-/releases/$WP/downloads/wayland-protocols-$WP.tar.xz"
echo "$WP_SHA256  wp.tar.xz" | sha256sum -c -
mkdir wp && tar xJf wp.tar.xz -C wp --strip-components=1
meson setup wp/build wp --prefix=/usr/local -Dtests=false >/dev/null
meson install -C wp/build >/dev/null
export PKG_CONFIG_PATH=/usr/local/share/pkgconfig
curl -fsSL -o noc.tar.gz "https://github.com/noctalia-dev/noctalia/releases/download/v$NOC/noctalia-v$NOC.tar.gz"
echo "$NOC_SHA256  noc.tar.gz" | sha256sum -c -
mkdir src && tar xzf noc.tar.gz -C src --strip-components=1
meson setup build src --buildtype=release --prefix=/usr -Dtests=disabled -Djemalloc=enabled
ninja -C build -j"$JOBS"
P=$W/pkg; DESTDIR=$P meson install -C build --no-rebuild >/dev/null
find "$P/usr/bin" "$P/usr/libexec" -type f -exec strip --strip-unneeded {} + 2>/dev/null || true
mkdir -p "$P/usr/share/doc/kwick-noctalia"
cp src/LICENSE "$P/usr/share/doc/kwick-noctalia/copyright"
mkdir -p debian && echo "Source: kwick-noctalia" > debian/control
deps=$(dpkg-shlibdeps -O --ignore-missing-info "$P/usr/bin/noctalia" "$P"/usr/libexec/noctalia/* 2>/dev/null | sed -n 's/^shlibs:Depends=//p')
mkdir -p "$P/DEBIAN"
cat > "$P/DEBIAN/control" <<EOF
Package: kwick-noctalia
Version: $VER
Architecture: $ARCH
Maintainer: KwickOS Developers <dev@kwickos.org>
Section: x11
Priority: optional
Depends: $deps, sound-theme-freedesktop
Recommends: upower, power-profiles-daemon
Conflicts: noctalia
Provides: noctalia (= $NOC)
Description: Noctalia $NOC desktop shell for KwickOS
 A sleek, customizable desktop shell crafted for Wayland.
 Noctalia (MIT) built from the pinned v$NOC release for Debian 13.
EOF
mkdir -p "$OUT/repo/pool/main"
dpkg-deb --root-owner-group -Zxz -b "$P" "$OUT/repo/pool/main/kwick-noctalia_${VER}_${ARCH}.deb" >/dev/null
echo "packaged kwick-noctalia $VER (Noctalia $NOC)"
