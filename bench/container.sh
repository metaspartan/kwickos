#!/bin/bash
# Usage: bench/container.sh [KWICKOS_IMAGE]
# Container image size, pull size, shell memory, install footprint and package counts.
# Prints raw lines and markdown tables. Keep the whole output in bench/results/.
set -uo pipefail
KW=${1:-ghcr.io/metaspartan/kwickos:latest}
ALPINE=${ALPINE:-alpine:3.24.4}
DEBIAN=${DEBIAN:-debian:trixie-slim}
UBUNTU=${UBUNTU:-ubuntu:26.04}
IMAGES="$KW $ALPINE $DEBIAN $UBUNTU"
RUN=(docker run --rm --cpus 6)
for i in $IMAGES; do docker pull -q "$i" >/dev/null; done

ms() { local n; n=$(date +%s%N); echo $(( n / 1000000 )); }
median() { sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}'; }

echo "# bench/container.sh $(date -u +%Y-%m-%dT%H:%MZ)"
echo "# docker $(docker version -f '{{.Server.Version}}') on $(docker info -f '{{.KernelVersion}}' 2>/dev/null)"
for img in $IMAGES; do echo "# $img $(docker image inspect -f '{{index .RepoDigests 0}}' "$img")"; done

echo
echo "## Container image (amd64)"
echo
echo "| image | uncompressed | gzip (pull size) | files | process memory of \`sh\` (anon+pagetables, 5 runs: median [min-max]) |"
echo "|---|---|---|---|---|"
for img in $IMAGES; do
  size=$(docker image inspect -f '{{.Size}}' "$img")
  gz=$(docker save "$img" | gzip -c | wc -c)
  files=$("${RUN[@]}" "$img" sh -c 'find / -xdev 2>/dev/null | wc -l')
  mem=$(for i in 1 2 3 4 5; do "${RUN[@]}" "$img" sh -c 'grep -E "^(anon|pagetables) " /sys/fs/cgroup/memory.stat' | awk '{s+=$2} END {print int(s/1024)}'; done | sort -n | tr '\n' ' ')
  set -- $mem
  awk -v i="$img" -v s="$size" -v g="$gz" -v f="$files" -v m="$3" -v lo="$1" -v hi="$5" \
    'BEGIN{printf "| %s | %.2f MB | %.2f MB | %s | %s KiB [%s-%s] |\n", i, s/1e6, g/1e6, f, m, lo, hi}'
done

echo
echo "## What is in the KwickOS image"
echo
"${RUN[@]}" "$KW" sh -c 'grep PRETTY_NAME /etc/os-release; for f in /usr/bin/kpkg /bin/busybox /sbin/kinit /usr/bin/kfetch; do [ -e "$f" ] && echo "$(wc -c <"$f") bytes $f"; done
  echo "TLS libraries: $(find / -xdev \( -name "libssl*" -o -name "libcrypto*" -o -name "libgnutls*" \) 2>/dev/null | wc -l)"
  echo "CA bundle: $(ls /etc/ssl/certs/ca-certificates.crt 2>/dev/null || echo none)"'
echo "# $ALPINE for comparison:"
"${RUN[@]}" "$ALPINE" sh -c 'echo "TLS libraries: $(find / -xdev \( -name "libssl*" -o -name "libcrypto*" \) 2>/dev/null | wc -l)"; echo "CA bundle: $(ls /etc/ssl/certs/ca-certificates.crt 2>/dev/null || echo none)"'

echo
echo "## Packages available (amd64, default sources)"
echo
echo "| system | source | packages |"
echo "|---|---|---|"
n=$("${RUN[@]}" "$ALPINE" sh -c 'echo "https://dl-cdn.alpinelinux.org/alpine/v3.24/community" >>/etc/apk/repositories; apk update -q >/dev/null 2>&1; apk search -q | sort -u | wc -l')
echo "| $ALPINE | main + community, x86_64 | $n |"
n=$("${RUN[@]}" "$DEBIAN" sh -c 'apt-get update -qq >/dev/null 2>&1; apt-cache dumpavail | grep "^Package: " | sort -u | wc -l')
echo "| $DEBIAN (the archive KwickOS's apt uses) | trixie, trixie-updates, trixie-security main, amd64 | $n |"

echo
echo "## Installing software (fresh container each, network time included)"
echo
echo "| image | task | wall time | rootfs after | after removing package indexes/caches |"
echo "|---|---|---|---|---|"
inst() {
  local img=$1; shift
  case $img in
    alpine*) cmd="apk add --no-cache $*" ;;
    debian*|ubuntu*) cmd="apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends $*" ;;
    *) cmd="apt update && apt install -y $*" ;;
  esac
  local s=$(ms)
  local out=$("${RUN[@]}" "$img" sh -c "{ $cmd; } >/dev/null 2>&1; echo rc=\$?; du -smx / 2>/dev/null | cut -f1; rm -rf /var/lib/apt/lists/* /var/cache/apt/* /var/cache/apk/* /var/lib/kpkg/lists/* /lib/apk/db/scripts.tar* 2>/dev/null; du -smx / 2>/dev/null | cut -f1" | tr '\n' ' ')
  local e=$(ms)
  set -- $out
  echo "| $img | install $pkgs ($1) | $(( (e-s) )) ms | ${2} MB | ${3} MB |"
}
for pkgs in curl python3; do for img in $IMAGES; do inst "$img" $pkgs; done; done
