#!/bin/sh
KINIT=${1:?usage: growroot-gpt.sh KINIT_BINARY  (run as root in a privileged throwaway container with sfdisk, losetup, mkfs.ext4)}
[ "$(id -u)" = 0 ] || { echo "run as root in a privileged throwaway container"; exit 2; }
for t in sfdisk losetup mkfs.ext4 truncate; do command -v $t >/dev/null || { echo "need $t"; exit 2; }; done
W=$(mktemp -d)
LOOP=
cleanup() {
  umount "$W/mnt" 2>/dev/null
  [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null
  rm -rf "$W"
}
trap cleanup EXIT
ln -s "$KINIT" "$W/kwick-growroot"
fail=0
ok() { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

attach() {
  LOOP=$(losetup -f --show -P "$1") || return 1
  n=${LOOP#/dev/}
  for p in /sys/class/block/${n}p*; do
    [ -e "$p/dev" ] || continue
    d=/dev/${p##*/}
    [ -b "$d" ] || mknod "$d" b $(tr ':' ' ' < "$p/dev")
  done
  [ -b "${LOOP}p$2" ]
}

detach() {
  umount "$W/mnt" 2>/dev/null
  losetup -d "$LOOP"
  LOOP=
}

run_case() {
  label=$1 kind=$2
  img="$W/$kind.img"
  rm -f "$img"
  truncate -s 64M "$img"
  if [ "$kind" = gpt ]; then
    printf 'label: gpt\nfirst-lba: 2048\nstart=1MiB, size=8MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI System"\nstart=9MiB, size=32MiB, type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709, name="kwick-root"\n' | sfdisk -q "$img"
  else
    printf 'label: dos\nunit: sectors\nstart=2048, size=16384, type=c\nstart=18432, size=65536, type=83\n' | sfdisk -q "$img"
  fi
  truncate -s 200M "$img"
  attach "$img" 2 || { bad "$label: no partition devices for the loop image"; return; }
  mkfs.ext4 -q -F -L kwick-root "${LOOP}p2"
  mkdir -p "$W/mnt"
  mount "${LOOP}p2" "$W/mnt" || { bad "$label: mount failed"; detach; return; }
  before=$(df -m "$W/mnt" | awk 'NR == 2 { print $2 }')
  "$W/kwick-growroot" "$W/mnt" > "$W/out" 2>&1
  rc=$?
  sed 's/^/      /' "$W/out"
  after=$(df -m "$W/mnt" | awk 'NR == 2 { print $2 }')
  psz=$(cat /sys/class/block/${LOOP#/dev/}p2/size)
  [ $rc = 0 ] && ok "$label: kwick-growroot exits 0" || bad "$label: kwick-growroot exited $rc"
  [ "$psz" -gt 300000 ] && ok "$label: the kernel sees the grown partition ($((psz / 2048)) MiB)" || bad "$label: partition still $((psz / 2048)) MiB"
  [ "$after" -gt $((before * 4)) ] && ok "$label: ext4 grew online from $before to $after MiB" || bad "$label: ext4 is $after MiB (was $before)"
  "$W/kwick-growroot" "$W/mnt" > "$W/out2" 2>&1
  [ $? = 0 ] && ! grep -q grown "$W/out2" && ok "$label: a second run changes nothing" || bad "$label: second run: $(cat "$W/out2")"
  detach
  v=$(sfdisk --verify "$img" 2>&1)
  if [ "$kind" = gpt ]; then
    echo "$v" | grep -qi 'no errors detected' && ok "$label: sfdisk --verify finds no errors" || bad "$label: sfdisk --verify: $v"
    echo "$v" | grep -qi 'backup' && bad "$label: $v" || ok "$label: the backup GPT header sits at the end of the disk"
    end=$(sfdisk -d "$img" | sed -n 's/^[^ ]*2 : start= *\([0-9]*\), size= *\([0-9]*\).*/\1 \2/p' | awk '{ print $1 + $2 - 1 }')
    [ -n "$end" ] && [ "$end" -gt 300000 ] && [ "$end" -le $((200 * 2048 - 34)) ] && ok "$label: the partition ends at sector $end, before the backup entries" || bad "$label: partition end '$end' is wrong"
    if command -v sgdisk >/dev/null; then
      sgdisk -v "$img" 2>&1 | grep -q 'No problems found' && ok "$label: sgdisk -v finds no problems" || bad "$label: sgdisk -v: $(sgdisk -v "$img" 2>&1 | tr '\n' ' ')"
    fi
    pm=$(od -An -tu4 -j $((446 + 12)) -N4 "$img" | tr -d ' ')
    [ "$pm" = $((200 * 2048 - 1)) ] && ok "$label: protective MBR covers the grown disk" || bad "$label: protective MBR size $pm"
  else
    echo "$v" | grep -qi 'no errors detected' && ok "$label: sfdisk --verify finds no errors" || bad "$label: sfdisk --verify: $v"
  fi
}

run_case "GPT (qcow2 image layout)" gpt
run_case "MBR (Raspberry Pi layout)" mbr

img="$W/bad.img"
truncate -s 64M "$img"
printf 'label: gpt\nfirst-lba: 2048\nstart=1MiB, size=8MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B\nstart=9MiB, size=32MiB, type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709\n' | sfdisk -q "$img"
truncate -s 200M "$img"
if attach "$img" 2; then
  mkfs.ext4 -q -F "${LOOP}p2"
  mount "${LOOP}p2" "$W/mnt"
  printf 'X' | dd of="$LOOP" bs=1 seek=$((512 + 40)) conv=notrunc status=none
  sync
  sum0=$(dd if="$LOOP" bs=512 count=34 status=none | md5sum)
  "$W/kwick-growroot" "$W/mnt" > "$W/out" 2>&1
  sum1=$(dd if="$LOOP" bs=512 count=34 status=none | md5sum)
  psz=$(cat /sys/class/block/${LOOP#/dev/}p2/size)
  detach
  [ "$sum0" = "$sum1" ] && [ "$psz" = 65536 ] && grep -q 'does not check out' "$W/out" && ok "a GPT with a bad header checksum is left alone" || bad "damaged GPT: $(cat "$W/out")"
else
  bad "damaged GPT: no partition devices"
fi
exit $fail
