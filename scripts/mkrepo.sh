#!/bin/bash
set -euo pipefail
DEVKEY=0
if [ "${1:-}" = --dev-key ]; then DEVKEY=1; shift; fi
SUITE=${1:-stable}; OUT=${OUT:-/out}; R="$OUT/repo"
cd "$R"
export GNUPGHOME=$(mktemp -d)
if [ -n "${KWICK_SIGNING_KEY:-}" ]; then
  bash /src/scripts/gpgimport.sh
elif [ "${CI:-}" = true ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "mkrepo: KWICK_SIGNING_KEY is empty; CI repositories are only signed with the archive key" >&2
  exit 1
elif [ "$DEVKEY" = 1 ]; then
  echo "mkrepo: signing with a throwaway dev key (--dev-key); clients need this repo's kwickos-archive-keyring.asc" >&2
  gpg --batch --passphrase-fd 3 --pinentry-mode loopback --quick-gen-key "KwickOS dev archive key <dev@kwickos.org>" ed25519 sign 1y 3< <(printf '') 2>/dev/null
else
  echo "mkrepo: KWICK_SIGNING_KEY is empty; pass --dev-key to sign with a throwaway dev key" >&2
  exit 1
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
gpg --batch --yes --local-user "$KEYID" --pinentry-mode loopback --passphrase-fd 3 --clearsign -o "dists/$SUITE/InRelease" "dists/$SUITE/Release" 3< <(printf '%s' "${KWICK_SIGNING_PASSPHRASE:-}")
gpg --batch --yes --local-user "$KEYID" --pinentry-mode loopback --passphrase-fd 3 -abs -o "dists/$SUITE/Release.gpg" "dists/$SUITE/Release" 3< <(printf '%s' "${KWICK_SIGNING_PASSPHRASE:-}")
rm -rf "$GNUPGHOME"
echo "repo ready: $R (key $KEYID)"
