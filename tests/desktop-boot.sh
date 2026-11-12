#!/bin/bash
# Boot the KwickOS Desktop live ISO in QEMU (UEFI, virtio-gpu) and verify the
# graphical session: plasmashell + kwin_wayland running as the live user.
# A screenshot of the display is saved for inspection.
#   desktop-boot.sh <iso> [screenshot.png]
set -uo pipefail
ISO=${1:?iso}; SHOT=${2:-/tmp/desktop.png}
TIMEOUT=${TIMEOUT:-240}
W=$(mktemp -d)
ACCEL=tcg; CPU=max; [ -w /dev/kvm ] && ACCEL=kvm && CPU=host
cp /usr/share/OVMF/OVMF_VARS_4M.fd "$W/vars.fd"
qemu-system-x86_64 -M q35,accel=$ACCEL -cpu $CPU -m 4096 -smp 4 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,file="$W/vars.fd" \
  -drive file="$ISO",media=cdrom,if=none,id=cd,readonly=on -device virtio-scsi-pci -device scsi-cd,drive=cd \
  -device virtio-vga -display none -device virtio-keyboard-pci -device virtio-tablet-pci \
  -nic user,model=virtio-net-pci -audiodev none,id=a0 -device intel-hda -device hda-duplex,audiodev=a0 \
  -serial file:"$W/serial.log" -monitor unix:"$W/mon",server,nowait -no-reboot &
QPID=$!
mon() { printf '%s\n' "$1" | socat - UNIX-CONNECT:"$W/mon" >/dev/null 2>&1 || python3 - "$W/mon" "$1" <<'EOF'
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); time.sleep(0.2); s.recv(4096)
s.sendall((sys.argv[2] + "\n").encode()); time.sleep(0.8); s.close()
EOF
}
t0=$(date +%s); ok=0
while kill -0 $QPID 2>/dev/null && [ $(( $(date +%s) - t0 )) -lt $TIMEOUT ]; do
  if grep -aq 'KWICK-DESKTOP-UP' "$W/serial.log" 2>/dev/null; then ok=1; break; fi
  sleep 2
done
ready=$(( $(date +%s) - t0 ))
sleep 20   # let the shell finish painting before the screenshot
mon "screendump $W/shot.ppm"
sleep 2
python3 - "$W/shot.ppm" "$SHOT" <<'EOF'
import sys, zlib, struct
d = open(sys.argv[1], 'rb').read()
parts = d.split(b'\n', 3); w, h = map(int, parts[1].split()); px = parts[3]
rows = b''.join(b'\x00' + px[y*w*3:(y+1)*w*3] for y in range(h))
c = lambda t, b: struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b) & 0xffffffff)
open(sys.argv[2], 'wb').write(b'\x89PNG\r\n\x1a\n' + c(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + c(b'IDAT', zlib.compress(rows, 6)) + c(b'IEND', b''))
print('screenshot', sys.argv[2], w, h)
EOF
kill $QPID 2>/dev/null; wait $QPID 2>/dev/null
tr -d '\r' < "$W/serial.log" | grep -aE 'kinit|KWICK|plasma|kwin|sddm|elogind' | tail -20
rm -rf "$W"
if [ $ok = 1 ]; then echo "DESKTOP BOOT: PASS (session up after ${ready}s)"; else echo "DESKTOP BOOT: FAIL"; exit 1; fi
