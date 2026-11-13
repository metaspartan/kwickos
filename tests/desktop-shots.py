#!/usr/bin/env python3
"""Boot a KwickOS Desktop live ISO under QEMU and take a scripted series of screenshots.
usage: desktop-shots.py <iso> <outdir> [script.txt]
script lines: wait N | key a-b-c | type some text | enter | shot name
"""
import os, socket, subprocess, sys, tempfile, time, zlib, struct
iso, outdir = sys.argv[1], sys.argv[2]
script = open(sys.argv[3]).read().splitlines() if len(sys.argv) > 3 else []
os.makedirs(outdir, exist_ok=True)
w = tempfile.mkdtemp()
subprocess.run(['cp', '/usr/share/OVMF/OVMF_VARS_4M.fd', f'{w}/vars.fd'])
kvm = os.access('/dev/kvm', os.W_OK)
q = subprocess.Popen(['qemu-system-x86_64', '-M', 'q35,accel=' + ('kvm' if kvm else 'tcg'), '-cpu', 'host' if kvm else 'max', '-m', '4096', '-smp', '4',
  '-drive', 'if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd', '-drive', f'if=pflash,format=raw,file={w}/vars.fd',
  '-drive', f'file={iso},media=cdrom,if=none,id=cd,readonly=on', '-device', 'virtio-scsi-pci', '-device', 'scsi-cd,drive=cd',
  '-device', 'virtio-vga', '-display', 'none', '-device', 'qemu-xhci', '-device', 'usb-kbd', '-device', 'usb-tablet',
  '-nic', 'user,model=virtio-net-pci', '-serial', f'file:{w}/serial.log', '-monitor', f'unix:{w}/mon,server,nowait', '-no-reboot'])
for _ in range(50):
    if os.path.exists(f'{w}/mon'): break
    time.sleep(0.2)
s = socket.socket(socket.AF_UNIX); s.connect(f'{w}/mon'); time.sleep(0.5); s.recv(65536)
def mon(c, d=0.15):
    s.sendall((c + '\n').encode()); time.sleep(d)
    s.settimeout(0.2)
    try: s.recv(65536)
    except Exception: pass
SHIFT = {'|': 'backslash', ':': 'semicolon', '_': 'minus', '>': 'dot', '<': 'comma', '"': 'apostrophe', '?': 'slash', '&': '7', '*': '8', '(': '9', ')': '0'}
PLAIN = {' ': 'spc', '-': 'minus', '.': 'dot', '/': 'slash', ';': 'semicolon', '\\': 'backslash', "'": 'apostrophe', ',': 'comma', '=': 'equal'}
def typ(t):
    for ch in t:
        if ch.isupper(): k = 'shift-' + ch.lower()
        elif ch in SHIFT: k = 'shift-' + SHIFT[ch]
        elif ch in PLAIN: k = PLAIN[ch]
        else: k = ch
        mon('sendkey ' + k, 0.06)
def shot(name):
    mon(f'screendump {w}/s.ppm', 1.5)
    d = open(f'{w}/s.ppm', 'rb').read(); p = d.split(b'\n', 3); W, H = map(int, p[1].split()); px = p[3]
    rows = b''.join(b'\x00' + px[y*W*3:(y+1)*W*3] for y in range(H))
    c = lambda t, b: struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b) & 0xffffffff)
    open(f'{outdir}/{name}.png', 'wb').write(b'\x89PNG\r\n\x1a\n' + c(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)) + c(b'IDAT', zlib.compress(rows, 6)) + c(b'IEND', b''))
    print('shot', name, W, H, flush=True)
t0 = time.time()
while time.time() - t0 < 420:
    if b'KWICK-DESKTOP-UP' in open(f'{w}/serial.log', 'rb').read(): break
    time.sleep(2)
else:
    print('desktop did not come up'); q.kill(); sys.exit(1)
print('session up after %ds' % (time.time() - t0), flush=True)
time.sleep(25)
for line in script:
    c, _, a = line.partition(' ')
    if c == 'wait': time.sleep(float(a))
    elif c == 'key': mon('sendkey ' + a, 0.4)
    elif c == 'type': typ(a)
    elif c == 'enter': mon('sendkey ret', 0.3)
    elif c == 'shot': shot(a)
    elif c == 'sh':  # run a command in the focused terminal and wait
        typ(a); mon('sendkey ret', 0.3)
q.kill(); q.wait()
print(open(f'{w}/serial.log', errors='replace').read()[-1500:])