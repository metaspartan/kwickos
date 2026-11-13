#!/bin/bash
set -euo pipefail
IMG=${1:?raw image}; MNT=${2:-/mnt/kroot}
START=$(sfdisk -J "$IMG" | python3 -c 'import json,sys; p=json.load(sys.stdin)["partitiontable"]["partitions"]; print(p[1]["start"]*512, p[0]["start"]*512, p[0]["size"]*512)')
set -- $START
mkdir -p "$MNT" "$MNT-esp"
L1=$(losetup -f --show -o "$1" "$IMG")
mount "$L1" "$MNT"
L2=$(losetup -f --show -o "$2" --sizelimit "$3" "$IMG")
mount "$L2" "$MNT-esp"
echo "root mounted at $MNT ($L1), ESP at $MNT-esp ($L2)"
