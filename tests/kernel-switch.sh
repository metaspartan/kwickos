#!/bin/bash
set -uo pipefail
MODE=${1:-efistub}
OUT=${OUT:-/out}; SRC=${SRC:-/src}; D="$OUT/amd64"
OLD=${OLD_VIRT:-$D/kernel-virt-old}
BOOT_TIMEOUT=${BOOT_TIMEOUT:-900}
W=$(mktemp -d)
LOGS=${LOGS:-$W}
case $MODE in efistub|grub) ;; *) echo "usage: kernel-switch.sh efistub|grub"; exit 2 ;; esac
[ -f "$OLD/version" ] || { echo "need an older virt kernel build in $OLD (OLD_VIRT=dir with version, vmlinuz, config)"; exit 2; }
ACCEL=tcg; CPU=max; [ -w /dev/kvm ] && ACCEL=kvm && CPU=host

pass=0; fail=0
check() {
  if grep -aqE "$3" "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1   (wanted: $3 in $2)"; fail=$((fail+1)); fi
}

mkdir -p "$W/pkg/amd64" "$W/share"
cp -a "$OLD" "$W/pkg/amd64/kernel-virt"; OUT=$W/pkg bash "$SRC/scripts/mkkernelpkg.sh" amd64 virt >/dev/null
rm -rf "$W/pkg/amd64/kernel-virt"; cp -a "$D/kernel-virt" "$W/pkg/amd64/kernel-virt"; OUT=$W/pkg bash "$SRC/scripts/mkkernelpkg.sh" amd64 virt >/dev/null
cp -a "$D/kernel-generic" "$W/pkg/amd64/kernel-generic"; OUT=$W/pkg bash "$SRC/scripts/mkkernelpkg.sh" amd64 generic >/dev/null
mkdir -p "$W/pkg/repo/pool/main"
if [ "$MODE" = efistub ]; then
  ( cd "$W/pkg/repo/pool/main" && apt-get update -qq >/dev/null 2>&1 && apt-get download -qq $(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances efibootmgr | grep '^[a-z0-9]' | sort -u) )
fi
OUT=$W/pkg bash "$SRC/scripts/mkrepo.sh" stable >/dev/null 2>&1
ls "$W/pkg/repo/pool/main"
OLDV=$(cat "$OLD/version"); NEWV=$(cat "$D/kernel-virt/version")
echo "old kernel $OLDV, new kernel $NEWV"
( cd "$W/pkg/repo" && python3 -m http.server 8080 >/dev/null 2>&1 ) & HTTP=$!
trap 'kill $HTTP 2>/dev/null; rm -rf "$W"' EXIT

cp "$W/pkg/repo/kwickos-archive-keyring.asc" "$W/share/"
cp "$SRC/rootfs/usr/sbin/kwick-kernel" "$SRC/rootfs/usr/sbin/kwick-kernel-install" "$SRC/rootfs/usr/lib/systemd/system/kwick-kernel-confirm.service" "$W/share/"

cp --sparse=always "$D/kwickos-amd64.img" "$W/disk.img"
cp /usr/share/OVMF/OVMF_VARS_4M.fd "$W/vars.fd"
ESPOFF=$((2048*512)); ROOTOFF=$((100352*512))
ROOTUUID=$(blkid -p -o value -s UUID --offset $ROOTOFF "$W/disk.img")
ESPUUID=$(blkid -p -o value -s UUID --offset $ESPOFF "$W/disk.img")
if [ "$MODE" = grub ]; then
  grub-mkimage -O x86_64-efi -o "$W/BOOTX64.EFI" -p /EFI/kwick/grub part_gpt part_msdos fat ext2 normal linux chain search search_fs_uuid configfile echo test loadenv gzio all_video
  mdel -i "$W/disk.img@@1M" ::EFI/BOOT/BOOTX64.EFI
  mcopy -i "$W/disk.img@@1M" "$W/BOOTX64.EFI" ::EFI/BOOT/BOOTX64.EFI
  mmd -i "$W/disk.img@@1M" ::EFI/kwick/grub 2>/dev/null
  mcopy -o -i "$W/disk.img@@1M" "$D/kernel-virt/vmlinuz" ::EFI/kwick/vmlinuz
  echo "$NEWV" > "$W/current"; mcopy -o -i "$W/disk.img@@1M" "$W/current" ::EFI/kwick/current
  cat > "$W/grub.cfg" <<EOF
set timeout=1
set default=0
insmod part_gpt
insmod fat
insmod ext2
insmod gzio
search --no-floppy --fs-uuid --set=root $ESPUUID
menuentry "KwickOS" {
	linux /EFI/kwick/vmlinuz root=UUID=$ROOTUUID
}
EOF
  mcopy -o -i "$W/disk.img@@1M" "$W/grub.cfg" ::EFI/kwick/grub/grub.cfg
  printf 'BOOTLOADER=grub\nFIRMWARE=uefi\nFS=ext4\nENCRYPT=0\nROOT_UUID=%s\nLUKS_UUID=\nESP_UUID=%s\nBOOT_UUID=\nDISK=/dev/vda\nEDITION=headless\n' "$ROOTUUID" "$ESPUUID" > "$W/share/install.conf"
fi

cat > "$W/share/lib.sh" <<'EOF'
mkdir -p /mnt/t; mount -t 9p -o trans=virtio t /mnt/t 2>/dev/null
kk() { echo "+ kwick-kernel $*"; kwick-kernel "$@"; echo "rc=$?"; }
facts() { echo "RUNNING uname=$(uname -r) modules=$([ -e /proc/modules ] && echo y || echo n) bootmode=$(ls /sys/firmware/efi >/dev/null 2>&1 && echo uefi)"; }
tools() {
  for f in kwick-kernel kwick-kernel-install; do cp /mnt/t/$f /usr/sbin/$f; chmod 755 /usr/sbin/$f; done
  mkdir -p /usr/lib/systemd/system /etc/systemd/system/multi-user.target.wants /etc/kwick
  cp /mnt/t/kwick-kernel-confirm.service /usr/lib/systemd/system/
  ln -sf /usr/lib/systemd/system/kwick-kernel-confirm.service /etc/systemd/system/multi-user.target.wants/kwick-kernel-confirm.service
  [ -f /etc/kwick/kernel.conf ] || echo 'CONFIRM_DELAY=8' > /etc/kwick/kernel.conf
  [ -f /mnt/t/install.conf ] && [ ! -f /etc/kwick/install.conf ] && cp /mnt/t/install.conf /etc/kwick/install.conf
  true
}
net() { n=0; while ! ip -4 addr show 2>/dev/null | grep 'inet ' | grep -vq ' 127\.'; do n=$((n+1)); [ $n -gt 90 ] && echo NONET && return 1; sleep 1; done; }
repo() {
  mv /etc/apt/sources.list.d/debian.sources /root/debian.sources.off 2>/dev/null
  mkdir -p /usr/share/keyrings && cp /mnt/t/kwickos-archive-keyring.asc /usr/share/keyrings/
  printf 'Types: deb\nURIs: http://10.0.2.2:8080\nSuites: stable\nComponents: main\nSigned-By: /usr/share/keyrings/kwickos-archive-keyring.asc\n' > /etc/apt/sources.list.d/kwickos.sources
}
settle() { sleep 14; }
EOF

boot() {
  local n=$1 log=$LOGS/phase$1.log fifo=$W/fifo
  { echo ". /mnt/t/lib.sh"; echo "$2"; echo "echo PHASE_END_$n"; echo "poweroff"; } > "$W/share/p$n.sh"
  rm -f "$fifo"; mkfifo "$fifo"; exec 3<>"$fifo"
  qemu-system-x86_64 -M q35,accel=$ACCEL -cpu $CPU -m 1024 -smp 2 -nographic -no-reboot -monitor none -serial stdio \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd -drive if=pflash,format=raw,file="$W/vars.fd" \
    -drive file="$W/disk.img",if=virtio,format=raw -nic user,model=virtio-net-pci \
    -virtfs local,path="$W/share",mount_tag=t,security_model=none,readonly=on <&3 >"$log" 2>&1 &
  local pid=$! sent=0 end=$(( $(date +%s) + BOOT_TIMEOUT ))
  while kill -0 $pid 2>/dev/null && [ $(date +%s) -lt $end ]; do
    if [ $sent = 0 ] && grep -aq '# $' "$log"; then echo 'mkdir -p /mnt/t; mount -t 9p -o trans=virtio t /mnt/t; sh /mnt/t/p'$n'.sh' >&3; sent=1; fi
    sleep 0.3
  done
  kill $pid 2>/dev/null; wait $pid 2>/dev/null; exec 3>&-
  tr -d '\r' < "$log" > "$log.txt"
  echo "--- phase $n"; sed -n '/^+ \|^rc=\|^RUNNING\|^boot path\|^running\|^default\|^previous\|^last trial\|^pending\|^KERNEL\|^[a-z0-9]*-[0-9.]* \|^MARK\|^LS\|^PHASE_END\|^trial\|^kwick-kernel\|^installing\|^refreshing\|^efibootmgr\|^Boot/p' "$log.txt" | head -${SHOW:-120}
}

if [ -n "${DEBUG_SCRIPT:-}" ]; then
  SHOW=400 boot 0 "$(cat "$DEBUG_SCRIPT")"
  tr -d '\r' < "$LOGS/phase0.log" | tail -${DEBUG_TAIL:-80}
  exit 0
fi

echo "=== $MODE: phase 1, booted from the image kernel ($NEWV): install two versions, try the older one"
boot 1 '
tools; net; repo
facts
kk install virt:'"${NEWV%%-*}"'
kk install virt:'"${OLDV%%-*}"' --no-default
kk list
kk status --json
echo MARK-state; cat /var/lib/kwick/kernel-state/default
[ "'$MODE'" = efistub ] && { echo LS-esp; ls /boot/efi/EFI/BOOT /boot/efi/EFI/kwick; }
[ "'$MODE'" = grub ] && { echo LS-grub; ls /boot/efi/EFI/kwick /boot/efi/EFI/kwick/k; grep -c menuentry /boot/efi/EFI/kwick/grub/grub.cfg; }
kk try '"${OLDV%%-*}"'
kk status
'
check "$MODE: new version installed and default" "$LOGS/phase1.log.txt" '"default":"virt-'"${NEWV%%-*}"'"'
check "$MODE: older version listed" "$LOGS/phase1.log.txt" 'virt-'"${OLDV%%-*}"' '
check "$MODE: trial armed" "$LOGS/phase1.log.txt" 'will boot once on the next reboot'

echo "=== $MODE: phase 2, one-shot trial of $OLDV must boot it, and the boot is confirmed"
boot 2 '
facts
settle
kk status
kk list
kk default '"${OLDV%%-*}"'
'
check "$MODE: trial booted the older kernel" "$LOGS/phase2.log.txt" "RUNNING uname=$OLDV"
check "$MODE: trial confirmed" "$LOGS/phase2.log.txt" 'last trial +ok virt-'"${OLDV%%-*}"
check "$MODE: pending trial cleared" "$LOGS/phase2.log.txt" 'default +virt-'"${NEWV%%-*}"

echo "=== $MODE: phase 3, default is now $OLDV (no trial), then roll back"
boot 3 '
facts
kk status
kk rollback
kk status
'
check "$MODE: default switch took effect on reboot" "$LOGS/phase3.log.txt" "RUNNING uname=$OLDV"
check "$MODE: rollback reports the previous default" "$LOGS/phase3.log.txt" 'rolled back from virt-'"${OLDV%%-*}"' to virt-'"${NEWV%%-*}"

echo "=== $MODE: phase 4, rollback took effect; try the older kernel with --promote"
boot 4 '
facts
kk try '"${OLDV%%-*}"' --promote
'
check "$MODE: rollback booted the newer kernel" "$LOGS/phase4.log.txt" "RUNNING uname=$NEWV"

echo "=== $MODE: phase 5, promoted trial becomes the default after confirmation; then a trial that is not confirmed"
boot 5 '
facts
settle
kk status
kk try '"${NEWV%%-*}"'
'
check "$MODE: promote trial ran the older kernel" "$LOGS/phase5.log.txt" "RUNNING uname=$OLDV"
check "$MODE: promote made it the default" "$LOGS/phase5.log.txt" 'default +virt-'"${OLDV%%-*}"

echo "=== $MODE: phase 6, trial kernel boots but the guest dies before confirmation (power-cycle)"
boot 6 '
facts
'
check "$MODE: trial boot ran the newer kernel" "$LOGS/phase6.log.txt" "RUNNING uname=$NEWV"

echo "=== $MODE: phase 7, back on the default; the unconfirmed trial is recorded as failed"
boot 7 '
facts
settle
kk status
'
check "$MODE: fell back to the default kernel" "$LOGS/phase7.log.txt" "RUNNING uname=$OLDV"
check "$MODE: unconfirmed trial recorded" "$LOGS/phase7.log.txt" 'last trial +failed virt-'"${NEWV%%-*}"

if [ "$MODE" = efistub ]; then
  echo "=== efistub: phase 7b, trial of an image the firmware cannot load"
  boot 71 '
net
mkdir -p /var/lib/kwick/kernels/virt-9.9.9; head -c 300000 /dev/urandom > /var/lib/kwick/kernels/virt-9.9.9/vmlinuz; echo 9.9.9-kwick > /var/lib/kwick/kernels/virt-9.9.9/release; echo virt > /var/lib/kwick/kernels/virt-9.9.9/flavor; : > /var/lib/kwick/kernels/virt-9.9.9/.complete
kk try 9.9.9
'
  boot 72 '
facts
settle
kk status
kk remove 9.9.9
'
  check "efistub: unloadable trial image fell back to the default kernel" "$LOGS/phase72.log.txt" "RUNNING uname=$OLDV"
  check "efistub: unloadable trial recorded as failed" "$LOGS/phase72.log.txt" 'last trial +failed virt-9.9.9'
fi

echo "=== $MODE: phase 8, switch flavor to generic (modules), remove and keep"
boot 8 '
net
kk install generic
mkdir -p /var/lib/kwick/kernels/virt-7.2.0; head -c 100000 /dev/zero > /var/lib/kwick/kernels/virt-7.2.0/vmlinuz; echo 7.2.0-kwick > /var/lib/kwick/kernels/virt-7.2.0/release; echo virt > /var/lib/kwick/kernels/virt-7.2.0/flavor; : > /var/lib/kwick/kernels/virt-7.2.0/.complete
kk list
kk keep 1
kk remove '"${OLDV%%-*}"'
kk remove virt-'"${NEWV%%-*}"'
kk list --json
'
check "$MODE: generic installed as default" "$LOGS/phase8.log.txt" 'generic-'"${NEWV%%-*}"'.*default'
check "$MODE: keep removed the stale retained kernel" "$LOGS/phase8.log.txt" 'removing virt-7.2.0'
check "$MODE: running/default kernels cannot be removed" "$LOGS/phase8.log.txt" 'is the running kernel|belongs to an installed package'

echo "=== $MODE: phase 9, generic kernel running"
boot 9 '
facts
kk status
'
check "$MODE: generic kernel (modules) booted" "$LOGS/phase9.log.txt" 'RUNNING uname='"$NEWV"' modules=y'
check "$MODE: running id is generic" "$LOGS/phase9.log.txt" 'running +generic-'"${NEWV%%-*}"

echo "kernel switch $MODE: $pass passed, $fail failed"
[ $fail = 0 ]
