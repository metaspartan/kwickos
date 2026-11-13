#!/bin/bash
set -euo pipefail
REPO=${1:?repo}; TAG=${2:?tag}; COMMIT=${3:?commit}; DEST=${4:?dest}
if [ -d "$DEST/.git" ] && [ "$(git -C "$DEST" rev-parse HEAD)" = "$COMMIT" ]; then
  exit 0
fi
rm -rf "$DEST"
git init -q "$DEST"
git -C "$DEST" remote add origin "$REPO"
git -C "$DEST" fetch -q --depth 1 origin "refs/tags/$TAG"
git -C "$DEST" checkout -q --detach FETCH_HEAD
got=$(git -C "$DEST" rev-parse HEAD)
[ "$got" = "$COMMIT" ] || { echo "pin mismatch for $REPO $TAG: got $got, want $COMMIT" >&2; rm -rf "$DEST"; exit 1; }
