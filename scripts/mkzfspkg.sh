#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}; FLAVOR=${2:-generic}
SRC=${SRC:-/src}; OUT=${OUT:-/out}; BUILD=${BUILD:-/build}; CACHE=${CACHE:-/cache}
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
eval "$(sed 's/\r$//' "$SRC/config/zfs.env")"
K="$OUT/$ARCH/kernel-$FLAVOR"; O="$BUILD/kernel-$ARCH-$FLAVOR"
[ -f "$K/version" ] || { echo "no kernel in $K: build the $FLAVOR kernel first"; exit 1; }
KREL=$(cat "$K/version"); KVER=${KREL%-kwick}
case $ARCH in
  amd64) KARCH=x86_64; CROSS=; HOSTM=x86_64 ;;
  arm64) KARCH=arm64; CROSS=aarch64-linux-gnu-; HOSTM=aarch64 ;;
  riscv64) KARCH=riscv; CROSS=riscv64-linux-gnu-; HOSTM=riscv64 ;;
  *) echo "unknown arch $ARCH"; exit 1 ;;
esac
[ "$(uname -m)" = "$HOSTM" ] && CROSS=
if [ "$FLAVOR" = apple ]; then KSRC="$BUILD/src/asahi-linux"; IMGPKG=kwick-kernel-asahi; else KSRC="$BUILD/src/linux-${KREL%%-*}"; IMGPKG=linux-image-kwick-$FLAVOR; fi
[ -f "$O/Module.symvers" ] || { echo "kernel tree $O has no Module.symvers: the flavor must be built with modules"; exit 1; }
[ -f "$KSRC/Makefile" ] || { echo "no kernel source at $KSRC"; exit 1; }
grep -q '^CONFIG_MODULES=y' "$O/.config" || { echo "$KREL has no module support"; exit 1; }

need_tools=""
for t in autoreconf automake libtoolize patch; do command -v "$t" >/dev/null 2>&1 || need_tools=1; done
XLIBC=""
if [ -n "$CROSS" ] && ! echo 'int main(void){return 0;}' | "${CROSS}gcc" -x c -o /dev/null - >/dev/null 2>&1; then
  XLIBC=libc6-dev-$ARCH-cross
fi
if [ -n "$need_tools$XLIBC" ]; then
  apt-get update -qq >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends autoconf automake libtool patch ${XLIBC:+"$XLIBC"} >/dev/null
fi

fetch() {
  [ -f "$2" ] && [ "$(sha256sum "$2" | cut -d' ' -f1)" = "$3" ] && return 0
  curl -fL --retry 3 -s -o "$2.part" "$1"
  got=$(sha256sum "$2.part" | cut -d' ' -f1)
  [ "$got" = "$3" ] || { echo "sha256 mismatch for $1 (got $got, want $3)"; rm -f "$2.part"; exit 1; }
  mv "$2.part" "$2"
}

mkdir -p "$CACHE"
TB="$CACHE/zfs-$ZFS_VERSION.tar.gz"
fetch "$ZFS_URL" "$TB" "$ZFS_SHA256"
for p in $ZFS_UPSTREAM_PATCHES; do
  fetch "https://github.com/openzfs/zfs/commit/${p%%:*}.diff" "$CACHE/zfs-${p%%:*}.diff" "${p#*:}"
done

W="$BUILD/zfs-$ZFS_VERSION-$ARCH-$FLAVOR"
rm -rf "$W"; mkdir -p "$W"
tar -C "$W" --strip-components=1 -xzf "$TB"
cd "$W"
for p in $ZFS_UPSTREAM_PATCHES; do
  echo ">> openzfs ${p%%:*}"
  patch -p1 -s --no-backup-if-mismatch < "$CACHE/zfs-${p%%:*}.diff"
done
if grep -q 'static_cpu_has(' include/os/linux/kernel/linux/simd_x86.h; then
  echo ">> openzfs 315bc75afc18 backport: cpu_feature_enabled() instead of static_cpu_has()"
  sed -i 's/\bstatic_cpu_has(/cpu_feature_enabled(/g' include/os/linux/kernel/linux/simd_x86.h module/zcommon/simd_stat.c
fi
for p in $ZFS_LOCAL_PATCHES; do
  echo ">> $p"
  sed 's/\r$//' "$SRC/config/zfs/$p" | patch -p1 -s --no-backup-if-mismatch
done

ZMAX=$(sed -n 's/^Linux-Maximum: *//p' META)
ZMIN=$(sed -n 's/^Linux-Minimum: *//p' META)
KMM=$(echo "$KREL" | cut -d. -f1,2)
EXP=""
if [ "$(printf '%s\n%s\n' "$ZMAX" "$KMM" | sort -V | tail -n 1)" != "$ZMAX" ]; then
  if [ "${ZFS_ALLOW_UNSUPPORTED:-}" = 1 ]; then
    echo "!! OpenZFS $ZFS_VERSION supports Linux $ZMIN to $ZMAX, kernel is $KMM: building with --enable-linux-experimental"
    EXP=--enable-linux-experimental
  else
    echo "!! OpenZFS $ZFS_VERSION supports Linux $ZMIN to $ZMAX, kernel is $KMM: no zfs modules for $KREL."
    echo "!! Bump ZFS_VERSION or add the upstream compat commits in config/zfs.env."
    exit 3
  fi
fi
echo ">> OpenZFS $ZFS_VERSION (Linux $ZMIN to $ZMAX) for $KREL ($ARCH/$FLAVOR)"

T0=$(date +%s)
autoreconf -fi > "$W/autoreconf.log" 2>&1 || { tail -30 "$W/autoreconf.log"; exit 1; }
KOPT=(KERNEL_ARCH="$KARCH")
[ -n "$CROSS" ] && KOPT+=(--host="${CROSS%-}" KERNEL_CROSS_COMPILE="$CROSS" KERNEL_CC="${CROSS}gcc")
env ARCH="$KARCH" CROSS_COMPILE="$CROSS" ./configure --with-config=kernel --with-linux="$KSRC" --with-linux-obj="$O" "${KOPT[@]}" $EXP > "$W/configure.log" 2>&1 || { tail -60 "$W/configure.log"; tail -40 config.log; exit 1; }
env ARCH="$KARCH" CROSS_COMPILE="$CROSS" make -C module -j"$(nproc)" > "$W/build.log" 2>&1 || { grep -E 'error|Error' "$W/build.log" | head -40; tail -40 "$W/build.log"; exit 1; }
echo ">> built in $(( $(date +%s) - T0 ))s"

KOS=$(find "$W/module" -name '*.ko' | sort)
for want in spl zfs; do
  echo "$KOS" | grep -q "/$want.ko\$" || { echo "missing $want.ko"; exit 1; }
done
for k in $KOS; do
  vm=$(modinfo -F vermagic "$k" | cut -d' ' -f1)
  [ "$vm" = "$KREL" ] || { echo "$k has vermagic $vm, want $KREL"; exit 1; }
done

PKG=kwick-zfs-modules-$KREL
VER=$ZFS_VERSION-$ZFS_PKG_REVISION
P=$(mktemp -d); chmod 755 "$P"
MD="$P/usr/lib/modules/$KREL/updates/zfs"
mkdir -p "$P/DEBIAN" "$MD" "$P/usr/share/doc/$PKG"
for k in $KOS; do
  cp "$k" "$MD/"
  "${CROSS}strip" --strip-debug "$MD/$(basename "$k")" 2>/dev/null || strip --strip-debug "$MD/$(basename "$k")" 2>/dev/null || true
done
xz --check=crc32 --lzma2=dict=1MiB "$MD"/*.ko
{
  echo "OpenZFS $ZFS_VERSION kernel modules built for Linux $KREL by KwickOS."
  echo "Source: $ZFS_URL"
  echo "sha256: $ZFS_SHA256"
  echo "Upstream commits applied: $(for p in $ZFS_UPSTREAM_PATCHES; do printf '%s ' "${p%%:*}"; done)"
  echo "Local patches: $ZFS_LOCAL_PATCHES"
  echo
  echo "These modules are licensed under the CDDL-1.0 and are shipped as a"
  echo "separate package, never linked into the KwickOS kernel image."
  echo
  cat "$W/COPYRIGHT" 2>/dev/null || true
  echo
  cat "$W/LICENSE" 2>/dev/null || true
} > "$P/usr/share/doc/$PKG/copyright"
deb_control "$P" "$PKG" "$VER" "$ARCH" kernel <<EOT
Depends: $IMGPKG (= $KVER-1), kmod
Provides: zfs-modules (= $ZFS_VERSION), kwick-zfs-modules (= $VER)
Conflicts: zfs-dkms
Description: OpenZFS $ZFS_VERSION kernel modules for KwickOS kernel $KREL
 Prebuilt spl and zfs modules from the pinned OpenZFS $ZFS_VERSION release,
 built in CI against exactly this kernel, so no DKMS, headers or compiler
 are needed. CDDL-licensed and kept in this separate package; the kernel
 image never contains ZFS code.
EOT
deb_script "$P" postinst <<EOT
#!/bin/sh
set -e
if [ "\$1" = configure ]; then
	depmod -a $KREL || true
fi
exit 0
EOT
deb_script "$P" postrm <<EOT
#!/bin/sh
set -e
if [ "\$1" = remove ] || [ "\$1" = purge ]; then
	depmod -a $KREL 2>/dev/null || true
fi
exit 0
EOT
deb_build "$P" "$PKG" "$VER" "$ARCH" "($ARCH)"

MPKG=kwick-zfs
[ "$FLAVOR" = generic ] || MPKG=kwick-zfs-$FLAVOR
MVER=$VER+k$KVER
P=$(mktemp -d); chmod 755 "$P"
mkdir -p "$P/DEBIAN" "$P/usr/share/doc/$MPKG"
printf 'OpenZFS %s for KwickOS: modules from %s, userland from Debian %s (contrib).\nCDDL-1.0, see %s.\n' \
  "$ZFS_VERSION" "$PKG" "$ZFS_USERLAND_SUITE" "/usr/share/doc/$PKG/copyright" > "$P/usr/share/doc/$MPKG/copyright"
deb_control "$P" "$MPKG" "$MVER" "$ARCH" kernel 8 <<EOT
Depends: $PKG (= $VER), zfsutils-linux (>= ${ZFS_VERSION%.*})
Recommends: zfs-zed
Conflicts: zfs-dkms
Description: OpenZFS for KwickOS (prebuilt modules plus Debian userland)
 Pulls in the prebuilt OpenZFS $ZFS_VERSION modules for kernel $KREL and the
 Debian zfsutils-linux userland. A new kernel brings a new version of this
 package, so apt upgrade keeps the modules in step with the kernel.
 Use 'kwick-storage install zfs' to set up the $ZFS_USERLAND_SUITE pin for a
 userland that matches the module version.
EOT
deb_build "$P" "$MPKG" "$MVER" "$ARCH" "($ARCH)"
