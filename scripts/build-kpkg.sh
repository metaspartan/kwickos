#!/bin/bash
# Build static kpkg for every arch (pure Go, no cgo).
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}
# Always build with the newest patched Go (security fixes in the stdlib
# end up statically linked into kpkg). go.mod pins the minimum toolchain.
export GOTOOLCHAIN=${GOTOOLCHAIN:-auto}
export GOPATH=${GOPATH:-/cache/go} GOCACHE=${GOCACHE:-/cache/go-build} GOFLAGS=-mod=mod CGO_ENABLED=0
cd "$SRC/src/kpkg"
[ -f go.sum ] || go mod tidy
go version
go vet ./...
go test ./... 2>&1 | tail -3
for arch in ${ARCHES:-amd64 arm64 riscv64}; do
  mkdir -p "$OUT/$arch/userland"
  GOOS=linux GOARCH=$arch go build -trimpath -buildvcs=false -ldflags="-s -w -buildid=" -o "$OUT/$arch/userland/kpkg" .
  echo "kpkg $arch: $(stat -c %s "$OUT/$arch/userland/kpkg") bytes"
done
