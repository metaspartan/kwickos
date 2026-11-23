#!/bin/bash
# Usage: bash bench/run.sh            (or: make bench)
# Runs every benchmark against the latest release and writes the raw output to bench/results/DATE-*.txt.
# Then copy the figures into bench/results/summary.json and run: uv run --with matplotlib bench/publish.py
# Limits: containers get 6 CPUs, everything runs under nice -n 19, and only one VM (2 vCPU) runs at a time.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RES="$ROOT/bench/results"; mkdir -p "$RES"
LAB=${LAB:-$ROOT/out/bench}; mkdir -p "$LAB/rel" "$LAB/cache"
TAG=${TAG:-$(gh release view --repo metaspartan/kwickos --json tagName -q .tagName)}
D=$(date -u +%Y-%m-%d)

gh release download "$TAG" --repo metaspartan/kwickos -D "$LAB/rel" --clobber \
  -p kwickos-amd64.iso -p kwickos-amd64.efi -p kwickos-amd64-initramfs.cpio.zst -p SHA256SUMS
( cd "$LAB/rel" && sha256sum -c --ignore-missing SHA256SUMS )

nice -n 19 bash "$ROOT/bench/artifacts.sh" "$TAG" | tee "$RES/$D-artifacts.txt"
nice -n 19 bash "$ROOT/bench/container.sh" | tee "$RES/$D-container.txt"
docker run --rm --cpus 6 --device /dev/kvm -v "$ROOT/bench:/bench:ro" -v "$LAB/rel:/rel:ro" -v "$LAB/cache:/cache" \
  kwick-builder bash /bench/vm.sh "${RUNS:-5}" | tee "$RES/$D-vm.txt"
