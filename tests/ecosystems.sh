#!/bin/bash
# Cross-ecosystem smoke test on a KwickOS container image:
#   - apk: Alpine packages (musl) next to Debian packages (glibc)
#   - bun: official installer (`curl | bash`, bash installed on demand)
#   tests/ecosystems.sh [image]
set -uo pipefail
IMG=${1:-kwickos:dev}
fail=0
check() { if echo "$2" | grep -q "$3"; then echo "PASS $1"; else echo "FAIL $1"; echo "$2" | tail -15; fail=1; fi; }

out=$(docker run --rm "$IMG" sh -c '
  apk add nodejs 2>&1 | tail -1
  node -e "console.log(\"alpine-node\", process.version)"
  apt update >/dev/null 2>&1 && apt install -y python3 >/dev/null 2>&1
  python3 -c "print(\"debian-python\")"
  ls /lib/ld-musl-* /lib64/ld-linux-* 2>/dev/null' 2>&1)
check "apk + apt side by side" "$out" "alpine-node v"
check "glibc + musl coexist" "$out" "debian-python"

out=$(docker run --rm "$IMG" sh -c '
  apt update >/dev/null 2>&1 && apt install -y curl >/dev/null 2>&1
  curl -fsSL https://bun.sh/install | bash >/dev/null 2>&1
  cd /tmp && echo "console.log(\"bun-ok\", Bun.version)" > a.ts && ~/.bun/bin/bun a.ts' 2>&1)
check "bun (latest) via official installer" "$out" "bun-ok"

out=$(docker run --rm "$IMG" sh -c 'rm -f /etc/apk/keys/*; apk --version' 2>&1)
check "apk bootstrap refuses untrusted packages" "$out" "untrusted signing key"
exit $fail
