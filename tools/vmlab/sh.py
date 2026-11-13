#!/usr/bin/env python3
import socket, sys, time, uuid, re

sock, cmd = sys.argv[1], sys.argv[2]
timeout = float(sys.argv[3]) if len(sys.argv) > 3 else 120
s = socket.socket(socket.AF_UNIX)
s.connect(sock)
s.settimeout(1)
tag = uuid.uuid4().hex[:8]
s.sendall(b"\n")
time.sleep(0.3)
try:
    s.recv(65536)
except Exception:
    pass
s.sendall(("%s\necho __END_%s_$?__\n" % (cmd, tag)).encode())
buf = b""
t0 = time.time()
pat = re.compile(rb"__END_" + tag.encode() + rb"_(\d+)__\r?\n")
while time.time() - t0 < timeout:
    try:
        d = s.recv(65536)
        if not d:
            break
        buf += d
    except socket.timeout:
        continue
    m = None
    for m in pat.finditer(buf):
        pass
    if m:
        out = buf[: m.start()].decode(errors="replace")
        out = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", out).replace("\r", "")
        lines = out.split("\n")
        print("\n".join(lines[1:]).rstrip())
        sys.exit(int(m.group(1)))
print(buf.decode(errors="replace"))
sys.exit(124)
