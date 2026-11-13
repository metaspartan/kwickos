#!/bin/bash
set -euo pipefail
TAR=${1:?rootfs tar}; NAME=${2:-desktop-vm}
O=/vm/isoout; mkdir -p $O/amd64 /vm/build
ln -sfn /out/amd64/kernel-generic $O/amd64/kernel-generic
OUT=$O BUILD=/vm/build bash /work/srctree/scripts/mkdesktop-iso.sh amd64 "$TAR"
mv $O/amd64/kwickos-amd64-desktop.iso /vm/$NAME.iso
ls -l /vm/$NAME.iso
