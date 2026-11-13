#!/bin/bash
set -euo pipefail
SRC=${1:?source qcow2}; DST=${2:?dest qcow2}; GB=${3:-24}
T=$(mktemp -d /work/mkdisk.XXXXXX)
qemu-img convert -O raw "$SRC" "$T/d.raw"
qemu-img resize -f raw "$T/d.raw" "${GB}G"
echo ', +' | sfdisk -q -N 2 "$T/d.raw"
START=$(sfdisk -J "$T/d.raw" | python3 -c 'import json,sys; p=json.load(sys.stdin)["partitiontable"]["partitions"][1]; print(p["start"], p["size"])')
set -- $START
truncate -s $(( $2 * 512 )) "$T/p2.img"
dd if="$T/d.raw" of="$T/p2.img" bs=512 skip="$1" count="$2" status=none conv=sparse
e2fsck -fy "$T/p2.img" >/dev/null || true
resize2fs "$T/p2.img" >/dev/null
dd if="$T/p2.img" of="$T/d.raw" bs=512 seek="$1" count="$2" conv=notrunc,sparse status=none
qemu-img convert -O qcow2 "$T/d.raw" "$DST"
rm -rf "$T"
qemu-img info "$DST" | head -4
