#!/bin/bash
set -euo pipefail
export MSYS_NO_PATHCONV=1
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && (pwd -W 2>/dev/null || pwd))
NAME=${NAME:-kwlab}
WORK=${WORK:-$ROOT/out/vmlab}
mkdir -p "$HERE/../../out/vmlab"
(cd "$HERE" && docker build -t kwick-vmlab .)
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --privileged \
  --device /dev/dxg -v /usr/lib/wsl:/usr/lib/wsl:ro \
  -v kwlab-vm:/vm -v "$ROOT":/src:ro -v "$ROOT/out":/out:ro -v "$WORK":/work \
  kwick-vmlab sleep infinity
echo "lab container: $NAME  (docker exec -it $NAME bash)"
