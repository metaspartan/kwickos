cybara_arch() { echo "amd64 arm64"; }
cybara_desc() { echo "Cybara: self-hosted open-source AI agent platform, CLI and gateway (cybara.ai)"; }

cybara_asset_arch() {
  case $ARCH in
    amd64) echo x64 ;;
    arm64) echo arm64 ;;
  esac
}

cybara_state() {
  if marked cybara && [ -x "$BINDIR/cybara" ]; then echo yes; else echo no; fi
}

cybara_latest() {
  ensure_curl || return 1
  aa=$(cybara_asset_arch)
  t=$(mktemp -d /var/tmp/kwick-agents.XXXXXX)
  curl -fsSL "https://api.github.com/repos/$CYBARA_REPO/releases/latest" -o "$t/rel.json" || { rm -rf "$t"; warn "could not read the latest Cybara release"; return 1; }
  tag=$(grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' "$t/rel.json" | head -n 1 | sed -E 's/.*"([^"]+)"$/\1/')
  rm -rf "$t"
  [ -n "$tag" ] || return 1
  url="$CYBARA_RELEASE_BASE/$tag/cybara-$tag-linux-$aa-cli"
  want=$(curl -fsSL "$url.sha256" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
  printf '%s' "$want" | grep -Eq '^[0-9a-f]{64}$' || { warn "vendor checksum for $tag is missing or malformed"; return 1; }
  CYBARA_TAG=$tag
  CYBARA_URL=$url
  CYBARA_SHA=$want
}

cybara_install() {
  aa=$(cybara_asset_arch)
  if [ -n "${AGENTS_LATEST:-}" ]; then
    cybara_latest || return 1
    say "Latest release $CYBARA_TAG; checksum comes from the vendor's .sha256 file, not from KwickOS."
  else
    CYBARA_TAG=v$CYBARA_VERSION
    CYBARA_URL="$CYBARA_RELEASE_BASE/$CYBARA_TAG/cybara-$CYBARA_TAG-linux-$aa-cli"
    CYBARA_SHA=$(pv CYBARA_SHA256)
  fi
  say "Downloading $CYBARA_URL"
  say "Expected sha256 $CYBARA_SHA"
  t=$(mktemp -d /var/tmp/kwick-agents.XXXXXX)
  fetch_verify "$CYBARA_URL" "$CYBARA_SHA" "$t/cybara" || { rm -rf "$t"; return 1; }
  install -m 755 "$t/cybara" "$BINDIR/cybara"
  rm -rf "$t"
  mark cybara
  say "Cybara $CYBARA_TAG installed to $BINDIR/cybara."
  say "Start it with 'cybara start'; the dashboard is at http://localhost:4269."
  return 0
}

cybara_remove() {
  rm -f "$BINDIR/cybara"
  unmark cybara
  say "Your Cybara data and settings in your home directory are kept."
  return 0
}
