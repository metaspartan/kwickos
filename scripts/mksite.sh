#!/bin/bash
set -euo pipefail

usage() {
  echo "usage: $0 SITE_DIR" >&2
  echo "       $0 --mirror [--dry-run] BASE_URL SITE_DIR" >&2
  exit 2
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)

assemble() {
  local S=$1
  mkdir -p "$S/img"
  cp -r "$ROOT/site/." "$S/"
  find "$ROOT/docs/img" -maxdepth 1 -type f ! -name '*-frames.png' -exec cp {} "$S/img/" \;
  touch "$S/.nojekyll"
  [ -f "$S/index.html" ] && [ -f "$S/404.html" ] && [ -f "$S/img/kwickos-logo.svg" ] || { echo "site assembly incomplete" >&2; exit 1; }
  echo "site: $(find "$S" -maxdepth 1 -type f | wc -l) top-level files, $(find "$S/img" -type f | wc -l) images in $S"
}

fetch() {
  curl -fsSL --retry 4 --retry-delay 3 --connect-timeout 20 -o "$2" "$1"
}

sha() { sha256sum "$1" | cut -d' ' -f1; }

safe_path() {
  case "$1" in
    /*|*..*|*'\'*) return 1 ;;
  esac
  return 0
}

mirror() {
  local DRY=0
  if [ "${1:-}" = --dry-run ]; then DRY=1; shift; fi
  local BASE=${1:?base url}; local S=${2:?site dir}
  BASE=${BASE%/}
  local SUITE=${SUITE:-stable}
  local W
  if [ $DRY = 1 ]; then W=$(mktemp -d); else W=$S; mkdir -p "$W"; fi
  local D="$W/dists/$SUITE"
  mkdir -p "$D"

  fetch "$BASE/kwickos-archive-keyring.asc" "$W/kwickos-archive-keyring.asc"
  grep -q 'BEGIN PGP PUBLIC KEY BLOCK' "$W/kwickos-archive-keyring.asc" || { echo "keyring is not an armored public key" >&2; exit 1; }
  for f in InRelease Release Release.gpg; do fetch "$BASE/dists/$SUITE/$f" "$D/$f"; done

  command -v gpg >/dev/null || { echo "gpg is required to verify the repository signatures" >&2; exit 1; }
  local G; G=$(mktemp -d)
  gpg --homedir "$G" --batch --quiet --import "$W/kwickos-archive-keyring.asc" 2>/dev/null
  gpg --homedir "$G" --batch --quiet --verify "$D/InRelease" 2>/dev/null || { rm -rf "$G"; echo "InRelease signature does not verify" >&2; exit 1; }
  gpg --homedir "$G" --batch --quiet --verify "$D/Release.gpg" "$D/Release" 2>/dev/null || { rm -rf "$G"; echo "Release.gpg signature does not verify" >&2; exit 1; }
  rm -rf "$G"
  echo "signatures: InRelease and Release.gpg verified"

  local idx; idx=$(awk '/^SHA256:/{s=1;next} /^[^ ]/{s=0} s&&NF==3{print $1, $2, $3}' "$D/Release")
  [ -n "$idx" ] || { echo "Release lists no index files" >&2; exit 1; }

  local nidx=0
  while read -r h size p; do
    case "$p" in
      main/binary-*/Packages|main/binary-*/Packages.gz|main/binary-*/Packages.xz) ;;
      *) continue ;;
    esac
    safe_path "$p" || { echo "unsafe index path $p" >&2; exit 1; }
    mkdir -p "$D/$(dirname "$p")"
    fetch "$BASE/dists/$SUITE/$p" "$D/$p"
    [ "$(sha "$D/$p")" = "$h" ] || { echo "sha256 mismatch: $p" >&2; exit 1; }
    [ "$(wc -c < "$D/$p" | tr -d ' ')" = "$size" ] || { echo "size mismatch: $p" >&2; exit 1; }
    nidx=$((nidx + 1))
  done <<< "$idx"
  [ $nidx -gt 0 ] || { echo "no Packages files in Release" >&2; exit 1; }

  local list="$W/.debs"
  : > "$list"
  local pk
  for pk in "$D"/main/binary-*/; do
    local src
    if [ -f "$pk/Packages" ]; then src=$(cat "$pk/Packages")
    elif [ -f "$pk/Packages.gz" ]; then src=$(gzip -dc "$pk/Packages.gz")
    elif [ -f "$pk/Packages.xz" ]; then src=$(xz -dc "$pk/Packages.xz")
    else continue; fi
    printf '%s\n\n' "$src" | awk '
      /^Filename: /{f=$2} /^SHA256: /{h=$2} /^Size: /{z=$2}
      /^$/{ if (f!="") { if (h=="" || z=="") { print "MISSING " f; } else print h, z, f } f=h=z="" }' >> "$list"
  done
  if grep -q '^MISSING ' "$list"; then grep '^MISSING ' "$list" >&2; echo "Packages entries without SHA256 or Size" >&2; exit 1; fi
  sort -u -o "$list" "$list"
  local ndeb; ndeb=$(grep -c . "$list" || true)
  [ "$ndeb" -gt 0 ] || { echo "mirror is empty: no packages listed" >&2; exit 1; }
  if [ "$(awk '{print $3}' "$list" | sort | uniq -d | head -1)" != "" ]; then echo "one Filename listed with different hashes" >&2; exit 1; fi

  local total=0 n=0
  while read -r h size f; do
    safe_path "$f" || { echo "unsafe Filename $f" >&2; exit 1; }
    case "$f" in pool/*.deb) ;; *) echo "unexpected Filename $f" >&2; exit 1 ;; esac
    if [ $DRY = 1 ]; then
      local len
      len=$(curl -fsSIL --retry 3 --connect-timeout 20 "$BASE/$f" | tr -d '\r' | awk 'tolower($1)=="content-length:"{v=$2} END{print v}')
      [ "$len" = "$size" ] || { echo "missing or wrong size on server: $f ($len != $size)" >&2; exit 1; }
    else
      mkdir -p "$W/$(dirname "$f")"
      fetch "$BASE/$f" "$W/$f"
      [ "$(sha "$W/$f")" = "$h" ] || { echo "sha256 mismatch: $f" >&2; exit 1; }
    fi
    total=$((total + size)); n=$((n + 1))
  done < "$list"
  rm -f "$list"

  if [ $DRY = 0 ]; then
    local found; found=$(find "$W/pool" -name '*.deb' | wc -l | tr -d ' ')
    [ "$found" -eq "$ndeb" ] || { echo "expected $ndeb debs, found $found" >&2; exit 1; }
  fi
  local mode=mirrored; [ $DRY = 1 ] && mode="checked (dry run, HEAD only)"
  echo "apt mirror: $nidx index files verified, $n packages $mode, $((total / 1048576)) MiB"
  [ $DRY = 1 ] && rm -rf "$W"
  return 0
}

case "${1:-}" in
  --mirror) shift; mirror "$@" ;;
  ""|-*) usage ;;
  *) assemble "$1" ;;
esac
