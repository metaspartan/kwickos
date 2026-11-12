#!/bin/bash
# Container benchmarks: KwickOS vs Alpine vs Debian slim vs Ubuntu.
#   bench/container.sh [kwickos-image]      (needs docker)
# Prints a markdown report. Every image is measured the same way.
set -uo pipefail
KW=${1:-kwickos:dev}
ALPINE=${ALPINE:-alpine:3.24}
IMAGES="$KW $ALPINE debian:trixie-slim ubuntu:24.04"
N=${N:-15}
for i in $IMAGES; do [ "$i" = "$KW" ] || docker pull -q "$i" >/dev/null; done

ms() { local n; n=$(date +%s%N); echo $(( n / 1000000 )); }
median() { sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}'; }

echo "## Container image (amd64)"
echo
echo "| image | uncompressed | gzip (pull size) | files | \`docker run true\` median | process memory of \`sh\` (anon+pagetables, median) |"
echo "|---|---|---|---|---|---|"
for img in $IMAGES; do
  size=$(docker image inspect -f '{{.Size}}' "$img")
  gz=$(docker save "$img" | gzip -c | wc -c)
  files=$(docker run --rm "$img" sh -c 'find / -xdev 2>/dev/null | wc -l')
  docker run --rm "$img" true # warm
  t=$(for i in $(seq $N); do s=$(ms); docker run --rm "$img" true; e=$(ms); echo $((e-s)); done | median)
  mem=$(for i in 1 2 3 4 5; do docker run --rm "$img" sh -c 'grep -E "^(anon|pagetables) " /sys/fs/cgroup/memory.stat' | awk '{s+=$2} END {print s}'; done | median)
  printf '| %s | %.2f MB | %.2f MB | %s | %s ms | %.0f KiB |\n' "$img" "$(echo "$size/1000000" | bc -l)" "$(echo "$gz/1000000" | bc -l)" "$files" "$t" "$(echo "$mem/1024" | bc -l)"
done

echo
echo "## Installing software (fresh container each, network time included)"
echo
echo "| image | task | wall time | rootfs after | after removing package indexes/caches |"
echo "|---|---|---|---|---|"
inst() { # image pkgs...
  local img=$1; shift
  local pkgs="$*"
  case $img in
    alpine*) cmd="apk add --no-cache $*" ;;
    debian*|ubuntu*) cmd="apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends $* >/dev/null" ;;
    *) cmd="apt update >/dev/null 2>&1 && apt install -y $* >/dev/null" ;;
  esac
  local s=$(ms)
  local out=$(docker run --rm "$img" sh -c "$cmd >/dev/null 2>&1; du -smx / 2>/dev/null | cut -f1; rm -rf /var/lib/apt/lists/* /var/cache/apt/* /var/cache/apk/* /lib/apk/db/scripts.tar* 2>/dev/null; du -smx / 2>/dev/null | cut -f1" | tr '\n' ' ')
  local e=$(ms)
  set -- $out
  echo "| $img | install $pkgs | $(( (e-s) )) ms | ${1} MB | ${2} MB |"
}
for img in $IMAGES; do inst "$img" curl; done
for img in $IMAGES; do inst "$img" python3; done
