#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}; SRC=${SRC:-/src}; OUT=${OUT:-/out}
TAR=${2:-$OUT/$ARCH/kwickos-rootfs-$ARCH.tar.gz}
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
VER=$(kwick_version)
P=$(mktemp -d); C="$P/usr/lib/kwick/core"; mkdir -p "$P/DEBIAN" "$C" "$P/etc"
U="$OUT/$ARCH/userland"
if [ -f "$U/kinit" ] && [ -f "$U/kpkg" ]; then
  install -m 755 "$U/kinit" "$C/kinit"
  install -m 755 "$U/kpkg" "$C/kpkg"
else
  [ -f "$TAR" ] || { echo "mkcorepkg: no $U/kinit and no rootfs $TAR" >&2; exit 1; }
  X=$(mktemp -d)
  tar -xzf "$TAR" -C "$X" ./usr/sbin/kinit ./usr/bin/kpkg
  install -m 755 "$X/usr/sbin/kinit" "$C/kinit"
  install -m 755 "$X/usr/bin/kpkg" "$C/kpkg"
  rm -rf "$X"
fi
for b in kinit kpkg; do
  case $(od -An -tx1 -j18 -N2 "$C/$b" | tr -d ' \n') in
    3e00) want=amd64 ;; b700) want=arm64 ;; f300) want=riscv64 ;; *) want=unknown ;;
  esac
  [ "$want" = "$ARCH" ] || { echo "mkcorepkg: $b is $want, not $ARCH" >&2; exit 1; }
done
sed 's/\r$//' "$SRC/scripts/mkrootfs.sh" | sed -n '/^cat > usr\/lib\/os-release <<EOF$/,/^EOF$/p' | sed '1d;$d' | sed "s/\$VERSION/$VER/g" > "$P/usr/lib/os-release"
grep -q "^VERSION_ID=\"$VER\"$" "$P/usr/lib/os-release" || { echo "mkcorepkg: could not take os-release from mkrootfs.sh" >&2; exit 1; }
echo "KwickOS $VER" > "$P/etc/kwick-release"
chmod 644 "$P/usr/lib/os-release" "$P/etc/kwick-release"
find "$P" -type d -exec chmod 755 {} +
deb_control "$P" kwick-core "$VER" "$ARCH" admin <<EOT
Replaces: kwick-base
Description: KwickOS init, package manager and release identity
 kinit, the PID 1 and service manager, kpkg, the apt and dpkg of KwickOS,
 and the release files (/etc/kwick-release, os-release). New images carry
 them in the base system; this package brings the current versions to
 systems installed from an older image. A new kinit takes over at the next
 boot, a new kpkg with the next apt command.
EOT
deb_script "$P" postinst <<'EOT'
#!/bin/sh
set -e
[ "$1" = configure ] || exit 0
for f in sbin/kinit bin/kpkg; do
  s=/usr/lib/kwick/core/${f#*/}
  d=/usr/$f
  [ -s "$s" ] || continue
  cmp -s "$s" "$d" && continue
  rm -f "$d.kwick-new"
  ln "$s" "$d.kwick-new" 2>/dev/null || cp -p "$s" "$d.kwick-new"
  chmod 755 "$d.kwick-new"
  mv -f "$d.kwick-new" "$d"
done
exit 0
EOT
deb_build "$P" kwick-core "$VER" "$ARCH" "($ARCH)"
