#!/bin/sh
if lsblk -J -b -o PATH,SIZE,FSTYPE,PARTTYPE,LABEL,PARTLABEL,TYPE "$1" 2>/dev/null; then
  exit 0
fi
d=${1#/dev/}
printf '{"blockdevices":[{"path":"%s","type":"disk","children":[' "$1"
first=1
for p in /sys/class/block/"$d"*; do
  [ -f "$p/partition" ] || continue
  n=${p##*/}
  size=$(( $(cat "$p/size") * 512 ))
  info=$(blkid "/dev/$n" 2>/dev/null)
  get() { printf '%s' "$info" | sed -n "s/.* $1=\"\\([^\"]*\\)\".*/\\1/p"; }
  [ $first = 1 ] || printf ','
  first=0
  printf '{"path":"/dev/%s","size":%s,"fstype":"%s","parttype":"%s","label":"%s","partlabel":"%s","type":"part"}' \
    "$n" "$size" "$(get TYPE)" "$(get PART_ENTRY_TYPE)" "$(get LABEL)" "$(get PARTLABEL)"
done
printf ']}]}\n'
