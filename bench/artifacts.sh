#!/bin/bash
# Usage: bench/artifacts.sh [KWICKOS_TAG]
# Download sizes of the KwickOS release files and of Alpine's ISOs, from the publishers' own listings.
# Needs gh and curl. Keep the whole output in bench/results/.
set -uo pipefail
TAG=${1:-$(gh release view --repo metaspartan/kwickos --json tagName -q .tagName)}
ALP=${ALP:-v3.24}
row() { while read -r n s; do awk -v n="$n" -v s="$s" 'BEGIN{printf "| %s | %s | %.1f |\n", n, s, s/1e6}'; done; }
echo "# bench/artifacts.sh $(date -u +%Y-%m-%dT%H:%MZ)"
echo
echo "## KwickOS $TAG release files"
echo
echo "| file | bytes | MB |"
echo "|---|---:|---:|"
gh release view "$TAG" --repo metaspartan/kwickos --json assets -q '.assets[] | "\(.name) \(.size)"' | sort | row
echo
echo "## Alpine $ALP ISOs and minirootfs (latest-releases.yaml; riscv64 has no virt ISO)"
echo
echo "| file | bytes | MB |"
echo "|---|---:|---:|"
for a in x86_64 aarch64 riscv64; do
  curl -fsSL "https://dl-cdn.alpinelinux.org/alpine/$ALP/releases/$a/latest-releases.yaml" |
    awk '/^-/{f=""} /file: alpine-.*(\.iso|minirootfs.*)$/{f=$2} /size:/ && f!=""{print f, $2; f=""}'
done | row
