KERNEL_ORG_RELEASE_KEYS="ABAF11C65A2970B130ABE3C479BE3E4300411886 647F28654894E3BD457199BE38DBBDC86092693E"
KERNEL_ORG_SUMS_KEYS="B8868C80BA62A1FFFAF5FDA9632D3A06589DA6B1 $KERNEL_ORG_RELEASE_KEYS"

kernel_sig_ok() {
  local status=$1 allowed=$2 fpr
  grep -q '^\[GNUPG:\] GOODSIG ' "$status" || return 1
  for fpr in $(awk '$2 == "VALIDSIG" { print $NF }' "$status"); do
    case " $allowed " in *" $fpr "*) return 0 ;; esac
  done
  return 1
}

kernel_fetch_verified() {
  local kver=$1 out=$2 major=${1%%.*} w f want got
  case $kver in *[!0-9.]* | '') echo "invalid kernel version $kver" >&2; return 1 ;; esac
  w=$(mktemp -d)
  for f in $KERNEL_ORG_RELEASE_KEYS B8868C80BA62A1FFFAF5FDA9632D3A06589DA6B1; do
    GNUPGHOME=$w gpg --batch --quiet --dearmor < "$SRC/config/kernel/keys/$f.asc" >> "$w/keys.gpg" || { rm -rf "$w"; return 1; }
  done
  local base="https://cdn.kernel.org/pub/linux/kernel/v$major.x"
  curl -fL --proto '=https' --retry 3 -o "$out.part" "$base/linux-$kver.tar.xz" &&
    curl -fsSL --proto '=https' --retry 3 -o "$w/sha256sums.asc" "$base/sha256sums.asc" &&
    curl -fsSL --proto '=https' --retry 3 -o "$w/linux.tar.sign" "$base/linux-$kver.tar.sign" || { rm -rf "$w" "$out.part"; return 1; }
  if ! gpgv --keyring "$w/keys.gpg" --status-fd 3 --output "$w/sums" "$w/sha256sums.asc" 3>"$w/sums.status" 2>"$w/sums.log" ||
    ! kernel_sig_ok "$w/sums.status" "$KERNEL_ORG_SUMS_KEYS"; then
    cat "$w/sums.log" >&2
    echo "sha256sums.asc for v$major.x is not signed by a pinned kernel.org key" >&2
    rm -rf "$w" "$out.part"
    return 1
  fi
  want=$(awk -v f="linux-$kver.tar.xz" '$2 == f { print $1 }' "$w/sums")
  got=$(sha256sum "$out.part" | awk '{ print $1 }')
  if [ -z "$want" ] || [ "$want" != "$got" ]; then
    echo "sha256 mismatch for linux-$kver ($got vs ${want:-missing})" >&2
    rm -rf "$w" "$out.part"
    return 1
  fi
  if ! xz -dc "$out.part" | gpgv --keyring "$w/keys.gpg" --status-fd 3 "$w/linux.tar.sign" - 3>"$w/tar.status" 2>"$w/tar.log" ||
    ! kernel_sig_ok "$w/tar.status" "$KERNEL_ORG_RELEASE_KEYS"; then
    cat "$w/tar.log" >&2
    echo "linux-$kver.tar is not signed by Linus Torvalds or Greg Kroah-Hartman" >&2
    rm -rf "$w" "$out.part"
    return 1
  fi
  sed -n 's/^gpgv: *Good signature from /linux-'"$kver"': good signature from /p' "$w/tar.log"
  rm -rf "$w"
  mv "$out.part" "$out"
}
