#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}; WORK=${WORK:-/work}
. "$SRC/config/darling.env"
KVER=$(tr -d '\r\n' < "$SRC/VERSION")
DVER="${DARLING_TAG#v}-${DARLING_PKG_REVISION}"
JOBS=${JOBS:-$(nproc)}
export DEBIAN_FRONTEND=noninteractive CCACHE_DIR=${CCACHE_DIR:-$WORK/ccache}
mkdir -p "$WORK" "$OUT/repo/pool/main"

apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  ca-certificates git git-lfs cmake ninja-build clang lld bison flex xz-utils pkg-config ccache \
  gcc-multilib libc6-dev-i386 libfuse-dev libudev-dev libcap-dev libcap2-bin libelf-dev \
  libglu1-mesa-dev libcairo2-dev libgl1-mesa-dev libegl1-mesa-dev libtiff-dev libfreetype6-dev \
  libxml2-dev libfontconfig1-dev libbsd-dev libxrandr-dev libxcursor-dev libgif-dev libpulse-dev \
  libavformat-dev libavcodec-dev libavutil-dev libswresample-dev libdbus-1-dev libxkbfile-dev \
  libssl-dev llvm-dev libvulkan-dev libcurl4-openssl-dev libedit-dev python3 binutils dpkg-dev file >/dev/null

D="$WORK/darling"
if [ ! -d "$D/.git" ]; then
  git lfs install --skip-repo
  export GIT_CLONE_PROTECTION_ACTIVE=false
  git clone -q --recursive --shallow-submodules --depth 1 --branch "$DARLING_TAG" https://github.com/darlinghq/darling.git "$D" \
    || { rm -rf "$D"; git clone -q --recursive https://github.com/darlinghq/darling.git "$D"; }
fi
cd "$D"
[ "$(git rev-parse HEAD)" = "$DARLING_COMMIT" ] || { echo "darling checkout $(git rev-parse HEAD) != pinned $DARLING_COMMIT" >&2; exit 1; }

mkdir -p "$WORK/build" && cd "$WORK/build"
if [ ! -f build.ninja ]; then
  CFLAGS="" CXXFLAGS="" CPPFLAGS="" LDFLAGS="" cmake -GNinja "$D" \
    -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DTARGET_i386=OFF -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
fi
ninja -j"$JOBS"

P="$WORK/stage"; rm -rf "$P"; mkdir -p "$P"
DESTDIR="$P" cmake --install . >/dev/null

mkdir -p "$P/DEBIAN"
needed=$(find "$P" -type f -exec sh -c 'file -b "$1" | grep -q "^ELF" && readelf -d "$1" 2>/dev/null' _ {} \; \
  | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | sort -u)
deps=""
for so in $needed; do
  p=$(dpkg -S "/usr/lib/x86_64-linux-gnu/$so" "/lib/x86_64-linux-gnu/$so" 2>/dev/null | head -1 | cut -d: -f1 || true)
  [ -n "$p" ] && deps="$deps $p"
done
deps=$(echo $deps | tr ' ' '\n' | sort -u | grep -v '^libc6$' | paste -sd, | sed 's/,/, /g')
size=$(du -sk "$P" | cut -f1)
cat > "$P/DEBIAN/control" <<EOF
Package: kwick-darling
Version: $DVER
Architecture: amd64
Maintainer: KwickOS Developers <dev@kwickos.org>
Section: utils
Priority: optional
Installed-Size: $size
Depends: libc6, fuse3 | fuse, uidmap${deps:+, $deps}
Description: Darling, a macOS compatibility layer, for KwickOS
 Darling $DARLING_TAG (commit ${DARLING_COMMIT:0:12}) built for x86_64 from upstream sources.
 Runs macOS command-line programs on Linux in userspace (darlingserver, no kernel module).
 Start a session with 'darling shell'. x86_64 only; GUI support is experimental.
EOF
cat > "$P/DEBIAN/postinst" <<'PI'
#!/bin/sh
[ "$1" = configure ] || exit 0
exit 0
PI
chmod 755 "$P/DEBIAN/postinst"
dpkg-deb --root-owner-group -Zxz -b "$P" "$OUT/repo/pool/main/kwick-darling_${DVER}_amd64.deb" >/dev/null
echo "packaged kwick-darling $DVER (kwickos $KVER) deps: $deps"