#!/bin/bash
# Generate a signed apt repository from /out/repo/pool (Debian layout).
#   mkrepo.sh [suite=stable]
# Signing: if KWICK_SIGNING_KEY (ASCII-armored secret key) is set it is
# imported and used; otherwise an ephemeral dev key is generated and its
# public part exported next to the repo (never use that for releases).
set -euo pipefail
SUITE=${1:-stable}; OUT=${OUT:-/out}; R="$OUT/repo"
cd "$R"
export GNUPGHOME=$(mktemp -d)
if [ -n "${KWICK_SIGNING_KEY:-}" ]; then
  bash /src/scripts/gpgimport.sh
else
  gpg --batch --passphrase '' --quick-gen-key "KwickOS dev archive key <dev@kwickos.org>" ed25519 sign 1y 2>/dev/null
fi
KEYID=$(gpg --batch --list-secret-keys --with-colons | awk -F: '/^sec/{print $5; exit}')
gpg --batch --armor --export "$KEYID" > kwickos-archive-keyring.asc
for arch in amd64 arm64 riscv64; do
  d="dists/$SUITE/main/binary-$arch"; mkdir -p "$d"
  dpkg-scanpackages --arch "$arch" --multiversion pool /dev/null 2>/dev/null > "$d/Packages"
  gzip -9nk -f "$d/Packages"; xz -9k -f "$d/Packages"
done
{
  echo "Origin: KwickOS"; echo "Label: KwickOS"; echo "Suite: $SUITE"; echo "Codename: $SUITE"
  echo "Date: $(date -Ru)"; echo "Architectures: amd64 arm64 riscv64"; echo "Components: main"
  echo "Acquire-By-Hash: no"
  echo "SHA256:"
  (cd "dists/$SUITE" && find main -type f | sort | while read -r f; do
     printf ' %s %16d %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$(stat -c %s "$f")" "$f"; done)
} > "dists/$SUITE/Release"
gpg --batch --yes --local-user "$KEYID" --pinentry-mode loopback --passphrase "${KWICK_SIGNING_PASSPHRASE:-}" --clearsign -o "dists/$SUITE/InRelease" "dists/$SUITE/Release"
gpg --batch --yes --local-user "$KEYID" --pinentry-mode loopback --passphrase "${KWICK_SIGNING_PASSPHRASE:-}" -abs -o "dists/$SUITE/Release.gpg" "dists/$SUITE/Release"
rm -rf "$GNUPGHOME"
echo "repo ready: $R (key $KEYID)"
