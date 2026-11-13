#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}; SRC=${SRC:-/src}; OUT=${OUT:-/out}
VER=$(tr -d '\r\n' < "$SRC/VERSION")
HYPRLAND=${HYPRLAND_VERSION:-v0.49.0}
HYPRUTILS=${HYPRUTILS_VERSION:-v0.8.0}
HYPRLANG=${HYPRLANG_VERSION:-v0.6.3}
HYPRCURSOR=${HYPRCURSOR_VERSION:-v0.1.12}
HYPRGRAPHICS=${HYPRGRAPHICS_VERSION:-v0.1.3}
AQUAMARINE=${AQUAMARINE_VERSION:-v0.8.0}
SCANNER=${HYPRWAYLAND_SCANNER_VERSION:-v0.4.4}
PROTOCOLS=${HYPRLAND_PROTOCOLS_VERSION:-v0.6.4}
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends ca-certificates curl git cmake ninja-build meson pkg-config gcc g++ make xz-utils \
  libwayland-dev wayland-protocols libpixman-1-dev libdrm-dev libinput-dev libseat-dev libudev-dev libxkbcommon-dev \
  libegl-dev libgles-dev libgbm-dev libcairo2-dev libpango1.0-dev libpugixml-dev libzip-dev librsvg2-dev libtomlplusplus-dev \
  libjpeg-dev libwebp-dev libpng-dev libmagic-dev libre2-dev libxcb1-dev libxcb-composite0-dev libxcb-ewmh-dev libxcb-icccm4-dev \
  libxcb-render-util0-dev libxcb-res0-dev libxcb-xfixes0-dev libxcb-errors-dev libxcb-util-dev libxcursor-dev libxkbcommon-x11-dev \
  libdisplay-info-dev hwdata libliftoff-dev libgl-dev libopengl-dev libuuid1 uuid-dev libxcb-present-dev libxcb-dri3-dev libxcb-shm0-dev libxcb-render0-dev libxcb-xinput-dev \
  libspng-dev libsystemd-dev
W=$(mktemp -d); STAGE=$W/stage; mkdir -p "$STAGE"; cd "$W"
build() {
  local name=$1 repo=$2 tag=$3; shift 3
  git clone -q --depth 1 --branch "$tag" "https://github.com/hyprwm/$repo.git" "$name"
  cmake -S "$name" -B "$name/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr "$@"
  cmake --build "$name/build" -j8
  DESTDIR=$STAGE cmake --install "$name/build"
  DESTDIR= cmake --install "$name/build"
}
build hyprwayland-scanner hyprwayland-scanner "$SCANNER"
git clone -q --depth 1 --branch "$PROTOCOLS" https://github.com/hyprwm/hyprland-protocols.git hyprland-protocols
meson setup hyprland-protocols/build hyprland-protocols --prefix=/usr
DESTDIR=$STAGE meson install -C hyprland-protocols/build
meson install -C hyprland-protocols/build
build hyprutils hyprutils "$HYPRUTILS"
build hyprlang hyprlang "$HYPRLANG"
build hyprgraphics hyprgraphics "$HYPRGRAPHICS"
build hyprcursor hyprcursor "$HYPRCURSOR"
build aquamarine aquamarine "$AQUAMARINE"
mkdir hyprland-src && curl -fsSL "https://github.com/hyprwm/Hyprland/releases/download/$HYPRLAND/source-$HYPRLAND.tar.gz" | tar xz -C hyprland-src --strip-components=1
cd hyprland-src
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DNO_SYSTEMD=ON -DNO_UWSM=ON -DNO_HYPRPM=ON
cmake --build build -j8
DESTDIR=$STAGE cmake --install build
cd "$W"
rm -rf "$STAGE/usr/include" "$STAGE/usr/lib/"*/pkgconfig "$STAGE/usr/lib/"*/cmake "$STAGE/usr/share/pkgconfig" "$STAGE/usr/lib/"*/*.a
find "$STAGE/usr/bin" "$STAGE/usr/lib" -type f \( -perm -u+x -o -name '*.so*' \) -exec strip --strip-unneeded {} + 2>/dev/null || true
apt-get install -y --no-install-recommends dpkg-dev >/dev/null
mkdir -p debian && echo "Source: kwick-hyprland" > debian/control
LIBDIR=$(ls -d "$STAGE"/usr/lib/*-linux-gnu)
deps=$(dpkg-shlibdeps -O --ignore-missing-info -l"$LIBDIR" -xkwick-hyprland "$STAGE/usr/bin/Hyprland" "$STAGE/usr/bin/hyprctl" "$STAGE/usr/bin/hyprcursor-util" 2>/dev/null | sed -n 's/^shlibs:Depends=//p')
P=$W/pkg; mkdir -p "$P/DEBIAN"; cp -a "$STAGE/usr" "$P/usr"
cat > "$P/DEBIAN/control" <<EOF
Package: kwick-hyprland
Version: $VER
Architecture: $ARCH
Maintainer: KwickOS Developers <dev@kwickos.org>
Section: x11
Priority: optional
Depends: $deps, xwayland, libseat1, libdisplay-info2, libliftoff0, libjpeg62-turbo, libwebp7, libpng16-16t64, librsvg2-2, libmagic1t64, libspng0, libtomlplusplus3t64
Description: Hyprland $HYPRLAND tiling Wayland compositor for KwickOS
 Hyprland and its hypr* libraries (hyprutils, hyprlang, hyprgraphics, hyprcursor,
 aquamarine) built from pinned upstream source for Debian 13, installed under /usr.
EOF
mkdir -p "$OUT/repo/pool/main"
dpkg-deb --root-owner-group -Zxz -b "$P" "$OUT/repo/pool/main/kwick-hyprland_${VER}_${ARCH}.deb" >/dev/null
echo "packaged kwick-hyprland $VER (Hyprland $HYPRLAND)"
