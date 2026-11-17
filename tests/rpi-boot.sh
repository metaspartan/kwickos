#!/bin/bash
set -uo pipefail
OUT=${OUT:-/out}; D="$OUT/arm64"
IMG=${IMG:-$D/kwickos-arm64-rpi.img}
TIMEOUT=${TIMEOUT:-900}; SDSIZE=${SDSIZE:-4G}
DTB=${DTB:-bcm2711-rpi-4-b.dtb}
CON=${CON:-ttyAMA1}
W=$(mktemp -d); LOG="$W/serial.log"
if [ ! -f "$IMG" ] && [ -f "$IMG.zst" ]; then zstd -dq "$IMG.zst" -o "$W/src.img"; IMG="$W/src.img"; fi
[ -f "$IMG" ] || { echo "no $IMG"; exit 1; }
cp --sparse=always "$IMG" "$W/sd.img"
truncate -s "$SDSIZE" "$W/sd.img"
OFF=$(( $(sfdisk -d "$W/sd.img" | awk -F'[=,]' '/start=/{print $2; exit}' | tr -d ' ') * 512 ))
for f in kernel8.img "$DTB" cmdline.txt config.txt; do mcopy -n -i "$W/sd.img@@$OFF" "::$f" "$W/$f" || { echo "boot partition lacks $f"; exit 1; }; done
fdtput -d "$W/$DTB" /soc/serial@7e201000/bluetooth 2>/dev/null || true
BASE=$(tr -d '\r\n' < "$W/cmdline.txt" | sed -e 's/console=[^ ]*//g' -e 's/  */ /g')
RUN="kwick-growroot+/;echo+KW-ROOT+\$(df+-m+/+|+awk+'NR==2{print+\$2}');echo+KW-MODEL+\$(tr+-d+'\\0'+</proc/device-tree/model);echo+KW-REL+\$(uname+-r);grep+/boot/firmware+/proc/mounts;kwick-rpi-boot+status;kwick-kernel+status;poweroff"
APPEND="console=$CON,115200 $BASE kwick.run=$RUN"
echo "cmdline: $APPEND"
Q=(qemu-system-aarch64 -M raspi4b -m 2G -kernel "$W/kernel8.img" -dtb "$W/$DTB" -append "$APPEND"
   -drive file="$W/sd.img",if=sd,format=raw -nographic -no-reboot -serial mon:stdio -monitor none)
t0=$(date +%s)
timeout "$TIMEOUT" "${Q[@]}" </dev/null >"$LOG" 2>&1
rc=$?
t1=$(date +%s)
tr -d '\r' < "$LOG" | grep -av '^$' > "$W/clean.log"
echo "---- serial log (raspi4b, $((t1 - t0)) s, qemu rc=$rc) ----"
grep -a -E 'Linux version|Machine model|mmc[0-9]|kinit|EXT4-fs|growroot|KW-|ready in|boot/firmware|^board|^kernel|^firmware|^boot path|Kernel panic|not syncing|no root' "$W/clean.log" | head -80
echo "---- tail ----"; tail -n ${TAIL:-25} "$W/clean.log"
ok=1
P2=$(sfdisk -d "$W/sd.img" | awk -F'[=,]' '/start=/{n++} /start=/ && n==2 {print $2 * 512, $4 * 512}' | tr -s ' ')
read -r P2OFF P2LEN <<<"$P2"
read -r BC LBS <<<"$(od -An -w24 -tu4 -j $((P2OFF + 1024 + 4)) -N 24 "$W/sd.img" | awk '{print $1, $6}')"
FSB=$(( BC * (1024 << LBS) ))
echo "partition 2: $((P2LEN >> 20)) MiB, ext4: $((FSB >> 20)) MiB, card: $SDSIZE"
[ "$((P2LEN >> 20))" -gt 3000 ] && [ "$((FSB >> 20))" -gt 3000 ] || { echo "root did not grow"; ok=0; }
grep -aq 'ready in [0-9]* ms' "$W/clean.log" || ok=0
grep -aq '^KW-REL .*-kwick-rpi' "$W/clean.log" || ok=0
grep -aq '/boot/firmware vfat' "$W/clean.log" || ok=0
if [ $ok = 1 ]; then echo "RESULT raspi4b ok wall_s=$((t1 - t0))"; rm -rf "$W"; exit 0; fi
echo "RESULT raspi4b FAIL wall_s=$((t1 - t0))"
[ -n "${KEEP:-}" ] && echo "kept $W" || rm -rf "$W"
exit 1
