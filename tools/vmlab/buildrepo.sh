#!/bin/bash
set -euo pipefail
OUT=${OUT:-/work/pkg}
GITSRC=/src
SRC=/work/srctree
rm -rf "$OUT" "$SRC"; mkdir -p "$OUT/repo/pool/main" "$SRC"
tar -C "$GITSRC" --exclude=./out --exclude=./build --exclude=./.git --exclude=./bench -cf - . | tar -C "$SRC" -xf -
find "$SRC" -type f -exec grep -Iq . {} \; -exec sed -i 's/\x0d$//' {} +
mkdir -p "$OUT/amd64"
cp -r /out/amd64/kernel-virt /out/amd64/kernel-generic "$OUT/amd64/"
export OUT SRC
for f in virt generic; do bash "$SRC/scripts/mkkernelpkg.sh" amd64 $f; done
[ -z "${EXTRA_DEBS:-}" ] || cp $EXTRA_DEBS "$OUT/repo/pool/main/"
bash "$SRC/scripts/mkgpupkg.sh"
bash "$SRC/scripts/mkgamingpkg.sh"
bash "$SRC/scripts/mkessentialspkg.sh"
bash "$SRC/scripts/mkupdatepkg.sh"
bash "$SRC/scripts/mkcorepkg.sh" amd64 /out/amd64/kwickos-rootfs-amd64.tar.gz
bash "$SRC/scripts/mkarchpkg.sh"
if command -v go >/dev/null 2>&1; then ARCHES=amd64 bash "$SRC/scripts/mkagentspkg.sh"; else echo "buildrepo: no Go toolchain, kwick-agents skipped (build it with kwick-builder and pass EXTRA_DEBS)"; fi
bash "$SRC/scripts/mkdesktoppkg.sh" amd64
bash "$SRC/scripts/mkrepo.sh" --dev-key stable
G="git -c safe.directory=$GITSRC -C $GITSRC"
{
  echo "head $($G rev-parse --short HEAD)"
  echo "diff_sha256 $($G diff HEAD | sha256sum | cut -c1-16)"
  echo "untracked_sha256 $($G ls-files -o --exclude-standard desktop scripts | sort | xargs -I{} sh -c "sha256sum $GITSRC/{}" | sha256sum | cut -c1-16)"
  echo "built $(date -u +%FT%TZ)"
} | tee "$OUT/tree-state.txt"
ls -l "$OUT/repo/pool/main"
