import hashlib
import io
import ipaddress
import os
import re
import tarfile
import time
import urllib.parse
import xml.etree.ElementTree as ET

from . import util

SEV = {"info": 0, "low": 1, "medium": 2, "high": 3}
CHECKSUM_KEYS = ("cksums", "md5sums", "sha1sums", "sha224sums", "sha256sums", "sha384sums", "sha512sums", "b2sums")
VCS_PREFIX = ("git+", "git://", "svn+", "svn://", "hg+", "bzr+", "fossil+")
KNOWN_HOSTS = (
    "github.com", "githubusercontent.com", "gitlab.com", "codeberg.org", "sourceforge.net", "sf.net", "pythonhosted.org",
    "pypi.org", "pypi.io", "crates.io", "npmjs.org", "npmjs.com", "kernel.org", "gnu.org", "gnome.org", "kde.org",
    "mozilla.org", "mozilla.net", "debian.org", "ubuntu.com", "launchpad.net", "bitbucket.org", "sr.ht", "freedesktop.org",
    "archlinux.org", "pkgbuild.com", "golang.org", "go.dev", "googlesource.com", "googleapis.com", "dl.google.com",
    "gitea.com", "savannah.nongnu.org", "nongnu.org", "apache.org", "python.org", "rubygems.org", "cpan.org",
    "metacpan.org", "hackage.haskell.org", "nodejs.org", "rust-lang.org", "videolan.org", "x.org", "xorg.freedesktop.org",
    "gstreamer.freedesktop.org", "qt.io", "openssl.org", "fedoraproject.org", "opensuse.org", "flathub.org", "jetbrains.com",
    "microsoft.com", "visualstudio.com", "mesa3d.org", "libsdl.org", "steampowered.com", "nvidia.com", "amd.com",
    "intel.com", "codeload.github.com", "objects.githubusercontent.com", "releases.hashicorp.com", "download.docker.com",
)
BAD_HOSTS = (
    "pastebin.com", "paste.ee", "hastebin.com", "ix.io", "0x0.st", "transfer.sh", "termbin.com", "ptpb.pw", "bit.ly",
    "tinyurl.com", "t.co", "goo.gl", "is.gd", "cdn.discordapp.com", "discord.com", "mega.nz", "anonfiles.com", "file.io",
    "catbox.moe", "gofile.io", "dropbox.com", "drive.google.com", "ngrok.io", "ngrok-free.app", "temp.sh", "filebin.net",
)
PATTERNS = [
    ("high", "pipe-to-shell", r"\b(curl|wget|fetch)\b[^\n|;&]*\|\s*(sudo\s+)?(ba|z|da|k|fi)?sh\b", "downloads a script and pipes it into a shell"),
    ("high", "eval-download", r"\beval\b[^\n]*\$\(\s*(curl|wget)", "evaluates code fetched from the network"),
    ("high", "decode-exec", r"base64\s+(-d|--decode)[^\n]*\|\s*(ba|z|da)?sh\b|\|\s*base64\s+(-d|--decode)\s*\)\"?\s*$", "decodes base64 and executes it"),
    ("medium", "base64-decode", r"\bbase64\s+(-d|--decode)\b|b64decode\(|from_base64|atob\(", "decodes base64 data (obfuscation)"),
    ("medium", "eval", r"(^|[;&|\s])eval\s+[\"'$`]", "uses eval on dynamic content"),
    ("high", "inline-interpreter", r"\b(python[0-9.]*|perl|ruby|node)\s+-[ce]\s+[\"'][^\n]*(exec|eval|system|socket|urlopen|b64decode|http)", "runs inline interpreter code with exec/network/decoding"),
    ("high", "hex-escapes", r"(\\x[0-9a-fA-F]{2}){8,}", "contains long hex-escaped strings (obfuscation)"),
    ("high", "encoded-blob", r"[A-Za-z0-9+/]{120,}={0,2}", "contains a long encoded blob (obfuscation)"),
    ("high", "reverse-shell", r"/dev/tcp/|\bnc\b[^\n]*\s-e\s|\bsocat\b[^\n]*exec:|\bmkfifo\b[^\n]*\bnc\b", "contains reverse-shell constructs"),
    ("high", "persistence", r"/etc/sudoers|crontab\s|/etc/cron\.|\.bashrc|\.zshrc|\.profile\b|authorized_keys|/etc/ld\.so\.preload|LD_PRELOAD=", "touches shell startup, cron, sudoers, SSH keys or the preload list"),
    ("high", "setuid", r"chmod\s+([ugoa]*\+s|[0-7]?[4-7][0-7]{3}\b)", "sets setuid/setgid bits"),
    ("medium", "chmod-777", r"chmod\s+(-R\s+)?0?777\b", "makes files world-writable"),
    ("medium", "rm-root", r"rm\s+-[a-zA-Z]*r[a-zA-Z]*f?\s+(/|~|\$HOME)(\s|$)", "removes broad paths"),
]
NET_CMDS = r"\b(curl|wget|aria2c|git\s+clone|git\s+fetch|git\s+pull|pip[0-9.]*\s+install|python[0-9.]*\s+-m\s+pip\s+install|npm\s+(install|ci|i)\b|yarn(\s+install)?\b|pnpm\s+(install|i)\b|go\s+(get|mod\s+download)|cargo\s+(install|fetch)|gem\s+install|bundle\s+install|composer\s+install|dotnet\s+restore|gradle\b|mvn\b)"
INSTALL_BAD = r"\b(curl|wget|systemctl\s+enable|useradd|usermod|chsh|passwd|setcap)\b"


def base():
    return util.conf("AUR_URL").rstrip("/")


def rpc_search(q, by="name-desc"):
    if len(q) < 2:
        raise util.Fail("query-too-short", "AUR searches need at least 2 characters", util.EXIT_USAGE)
    d = util.http_json("%s/rpc/v5/search/%s?by=%s" % (base(), util.quote(q), by))
    if d.get("type") == "error":
        raise util.Fail("aur-error", "AUR: " + str(d.get("error")))
    return d.get("results") or []


def rpc_info(names):
    out = {}
    names = list(dict.fromkeys(names))
    for i in range(0, len(names), 100):
        chunk = names[i:i + 100]
        q = "&".join("arg[]=" + util.quote(n) for n in chunk)
        d = util.http_json("%s/rpc/v5/info?%s" % (base(), q))
        if d.get("type") == "error":
            raise util.Fail("aur-error", "AUR: " + str(d.get("error")))
        for r in d.get("results") or []:
            out[r["Name"]] = r
    return out


def history(pkgbase):
    text = util.http_get("%s/cgit/aur.git/atom/?h=%s" % (base(), util.quote(pkgbase)))
    ns = {"a": "http://www.w3.org/2005/Atom"}
    try:
        root = ET.fromstring(text)
    except ET.ParseError:
        raise util.Fail("aur-error", "could not read the AUR history of " + pkgbase)
    out = []
    for e in root.findall("a:entry", ns):
        cid = (e.findtext("a:id", "", ns) or "").strip()
        if cid.startswith("urn:sha1:"):
            cid = cid[9:]
        if not re.fullmatch(r"[0-9a-f]{40}", cid):
            continue
        out.append({
            "commit": cid,
            "subject": (e.findtext("a:title", "", ns) or "").strip(),
            "author": (e.findtext("a:author/a:name", "", ns) or "").strip(),
            "email": (e.findtext("a:author/a:email", "", ns) or "").strip(),
            "date": (e.findtext("a:updated", "", ns) or e.findtext("a:published", "", ns) or "").strip(),
        })
    if not out:
        raise util.Fail("not-found", "no AUR git history for " + pkgbase, util.EXIT_NOTFOUND)
    return out


def commit_tree(pkgbase, commit):
    html = util.http_get("%s/cgit/aur.git/commit/?h=%s&id=%s" % (base(), util.quote(pkgbase), commit))
    m = re.search(r"<th>tree</th><td[^>]*><a[^>]*>([0-9a-f]{40})</a>", html)
    if not m:
        raise util.Fail("bad-snapshot", "could not read the tree of AUR commit " + commit)
    return m.group(1)


def git_tree(entries):
    tree = {}
    for rel, (mode, data) in entries.items():
        parts = rel.split("/")
        node = tree
        for p in parts[:-1]:
            node = node.setdefault(p, {})
        node[parts[-1]] = (mode, data)

    def obj(kind, body):
        return hashlib.sha1(b"%s %d\0" % (kind, len(body)) + body).digest()

    def walk(node):
        items = []
        for name, v in node.items():
            if isinstance(v, dict):
                items.append((name.encode() + b"/", b"40000 " + name.encode() + b"\0" + walk(v)))
            else:
                mode, data = v
                items.append((name.encode(), mode + b" " + name.encode() + b"\0" + obj(b"blob", data)))
        items.sort(key=lambda x: x[0])
        return obj(b"tree", b"".join(i[1] for i in items))

    return walk(tree).hex()


def snapshot(pkgbase, commit):
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise util.Fail("bad-commit", "commit must be a full 40-character git hash", util.EXIT_USAGE)
    want = commit_tree(pkgbase, commit)
    last = None
    for name in ("%s.tar.gz" % commit, "aur-%s.tar.gz" % commit):
        try:
            data = util.http_get("%s/cgit/aur.git/snapshot/%s" % (base(), name), binary=True, timeout=120)
            files, entries = _read_snapshot(data)
        except (util.Fail, tarfile.TarError) as e:
            last = e
            continue
        got = git_tree(entries)
        if got == want:
            if "PKGBUILD" not in files or ".SRCINFO" not in files:
                raise util.Fail("bad-snapshot", "AUR commit %s has no PKGBUILD or .SRCINFO" % commit[:12])
            return files
        last = util.Fail("bad-snapshot", "snapshot tree %s does not match commit tree %s" % (got[:12], want[:12]))
    raise util.Fail("bad-snapshot", "could not fetch a verified snapshot of AUR commit %s: %s" % (commit[:12], getattr(last, "message", last)))


def _read_snapshot(data):
    files = {}
    entries = {}
    if not data:
        raise util.Fail("bad-snapshot", "empty snapshot")
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as t:
        for m in t.getmembers():
            parts = m.name.split("/", 1)
            if len(parts) < 2 or not parts[1]:
                continue
            rel = parts[1].rstrip("/")
            if rel.startswith("/") or ".." in rel.split("/"):
                raise util.Fail("bad-snapshot", "unsafe path in AUR snapshot: " + rel)
            if m.isfile():
                if m.size > 8 << 20:
                    raise util.Fail("bad-snapshot", "file too large in AUR snapshot: " + rel)
                files[rel] = t.extractfile(m).read()
                entries[rel] = (b"100755" if m.mode & 0o111 else b"100644", files[rel])
            elif m.issym():
                files[rel] = ("symlink", m.linkname)
                entries[rel] = (b"120000", m.linkname.encode())
    return files, entries


def digest(files):
    h = hashlib.sha256()
    for k in sorted(files):
        v = files[k]
        h.update(k.encode() + b"\0")
        h.update(v if isinstance(v, bytes) else ("->" + v[1]).encode())
        h.update(b"\0")
    return h.hexdigest()


def parse_srcinfo(text):
    info = {"pkgbase": None, "pkgnames": [], "base": {}, "pkgs": {}}
    cur = None
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or " = " not in line:
            continue
        k, v = line.split(" = ", 1)
        if k == "pkgbase":
            info["pkgbase"] = v
            cur = info["base"]
            continue
        if k == "pkgname":
            info["pkgnames"].append(v)
            cur = info["pkgs"].setdefault(v, {})
            continue
        if cur is None:
            continue
        cur.setdefault(k, []).append(v)
    return info


def si(info, key, pkg=None, arch="x86_64"):
    vals = []
    for k in (key, key + "_" + arch):
        if pkg and k in info["pkgs"].get(pkg, {}):
            vals += info["pkgs"][pkg][k]
        elif k in info["base"]:
            vals += info["base"][k]
    return vals


def full_version(info):
    b = info["base"]
    v = "%s-%s" % (b.get("pkgver", ["0"])[0], b.get("pkgrel", ["1"])[0])
    if b.get("epoch"):
        v = "%s:%s" % (b["epoch"][0], v)
    return v


def split_source(s):
    name = None
    url = s
    if "::" in s:
        name, url = s.split("::", 1)
    return name, url


def is_vcs(url):
    return url.startswith(VCS_PREFIX)


def host_of(url):
    u = url
    for p in VCS_PREFIX:
        if u.startswith(p) and "://" in u[len(p) - 1:]:
            u = u[len(p):] if p.endswith("+") else u
            break
    try:
        return (urllib.parse.urlparse(u).hostname or "").lower()
    except ValueError:
        return ""


def host_known(host, upstream):
    if not host:
        return False
    for h in KNOWN_HOSTS + tuple(x for x in upstream if x):
        if host == h or host.endswith("." + h):
            return True
    return False


def host_bad(host):
    for h in BAD_HOSTS:
        if host == h or host.endswith("." + h):
            return True
    try:
        ipaddress.ip_address(host.strip("[]"))
        return True
    except ValueError:
        return False


def functions(text):
    out = {}
    for m in re.finditer(r"(?m)^\s*(?:function\s+)?(build|check|prepare|pkgver|package(?:_[\w.+-]+)?)\s*\(\s*\)\s*\{", text):
        depth = 0
        i = m.end() - 1
        start = i
        quote = None
        while i < len(text):
            c = text[i]
            if quote:
                if c == "\\" and quote == '"':
                    i += 2
                    continue
                if c == quote:
                    quote = None
            elif c in "\"'" and text[i - 1] != "\\":
                quote = c
            elif c == "#" and (i == 0 or text[i - 1] in " \t\n"):
                nl = text.find("\n", i)
                i = len(text) if nl < 0 else nl
                continue
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        out[m.group(1)] = (text[start:i + 1], text.count("\n", 0, m.start()) + 1)
    return out


def line_of(text, pos):
    return text.count("\n", 0, pos) + 1


def finding(sev, fid, msg, file=None, line=None, excerpt=None):
    f = {"severity": sev, "id": fid, "message": msg}
    if file:
        f["file"] = file
    if line:
        f["line"] = line
    if excerpt:
        f["excerpt"] = excerpt[:200]
    return f


def scan_text(name, text, findings):
    for sev, fid, rx, msg in PATTERNS:
        for m in re.finditer(rx, text, re.M):
            ln = line_of(text, m.start())
            line = text.splitlines()[ln - 1] if text else ""
            if fid == "encoded-blob" and re.match(r"\s*(\w*sums(_\w+)?|validpgpkeys|_?\w*commit\w*|_?\w*sha\w*|pkgver|_?\w*hash\w*)\s*=", line):
                continue
            if fid == "encoded-blob" and re.fullmatch(r"\s*['\"]?[0-9a-f]+['\"]?\s*\)?\s*", line):
                continue
            s, mtxt = sev, msg
            if fid == "persistence" and "pkgdir" in line:
                s, mtxt = "medium", "packages a file into a cron, shell startup, sudoers or preload location"
            elif fid == "setuid":
                s, mtxt = "medium", "sets setuid/setgid bits (they have no effect for programs started through kwick-arch)"
            findings.append(finding(s, fid, mtxt, name, ln, line.strip()))
            break


def days_since(ts):
    return (time.time() - ts) / 86400 if ts else None


def iso_days(s):
    try:
        return days_since(time.mktime(time.strptime(s[:19], "%Y-%m-%dT%H:%M:%S")))
    except (ValueError, TypeError):
        return None


def meta_findings(meta):
    f = []
    if not meta:
        return f
    votes = meta.get("NumVotes") or 0
    pop = meta.get("Popularity") or 0
    age = days_since(meta.get("FirstSubmitted"))
    if not meta.get("Maintainer"):
        f.append(finding("medium", "orphaned", "the package is orphaned (no maintainer reviews updates)"))
    if meta.get("OutOfDate"):
        f.append(finding("low", "out-of-date", "flagged out of date on %s" % time.strftime("%Y-%m-%d", time.gmtime(meta["OutOfDate"]))))
    if age is not None and age < 14 and votes < 5:
        f.append(finding("high", "new-package", "first submitted %d day(s) ago and has %d vote(s); new AUR packages with no track record were used to spread malware" % (int(age), votes)))
    elif age is not None and age < 60:
        f.append(finding("medium", "young-package", "first submitted %d day(s) ago" % int(age)))
    if votes == 0:
        f.append(finding("medium", "no-votes", "nobody has voted for this package"))
    elif votes < 10 or pop < 0.1:
        f.append(finding("low", "low-popularity", "%d vote(s), popularity %.3f" % (votes, pop)))
    lm = days_since(meta.get("LastModified"))
    if lm is not None and lm < 3:
        f.append(finding("low", "recently-changed", "changed %.1f day(s) ago; read the latest changes" % lm))
    if meta.get("Maintainer") and meta.get("Submitter") and meta["Maintainer"] != meta["Submitter"] and lm is not None and lm < 30:
        f.append(finding("low", "maintainer-differs", "maintained by %s, originally submitted by %s, changed within 30 days" % (meta["Maintainer"], meta["Submitter"])))
    return f


def history_findings(hist):
    f = []
    if len(hist) < 2:
        return f
    newest = hist[0]
    age = iso_days(newest["date"])
    older = {h["email"] or h["author"] for h in hist[1:]}
    who = newest["email"] or newest["author"]
    if age is not None and age < 30 and who not in older:
        f.append(finding("medium", "new-committer", "the latest commit (%s) is by %s, who did not author any earlier commit in the visible history" % (newest["commit"][:12], newest["author"] or who)))
    return f


def risk(findings):
    top = max([SEV[f["severity"]] for f in findings] or [0])
    return "high" if top >= 3 else "medium" if top == 2 else "low"


def analyze(files, info, meta, hist):
    findings = []
    pkgbuild = files["PKGBUILD"].decode("utf-8", "replace")
    texts = {}
    for name, data in files.items():
        if isinstance(data, tuple):
            target = data[1]
            if target.startswith("/") or ".." in target.split("/"):
                findings.append(finding("medium", "symlink", "symlink %s points to %s" % (name, target), name))
            continue
        if b"\0" in data[:4096]:
            if name.startswith("keys/pgp/"):
                findings.append(finding("info", "pgp-key-file", "ships a PGP key used to verify sources", name))
            else:
                findings.append(finding("medium", "binary-file", "the AUR repository ships a binary file", name))
            continue
        texts[name] = data.decode("utf-8", "replace")
    for name, text in texts.items():
        if name == ".SRCINFO":
            continue
        scan_text(name, text, findings)
    for fn, (body, ln) in functions(pkgbuild).items():
        for m in re.finditer(NET_CMDS, body):
            sev = "low" if fn in ("prepare", "pkgver") else "medium"
            findings.append(finding(sev, "network-in-" + fn.split("_")[0], "%s() uses the network (%s); kwick-arch builds without network after the source download" % (fn, m.group(1)), "PKGBUILD", ln + body.count("\n", 0, m.start()), body[m.start():m.start() + 80].split("\n")[0]))
            break
    for name in info["base"].get("install", []) + [v for p in info["pkgs"].values() for v in p.get("install", [])]:
        text = texts.get(name)
        if text:
            m = re.search(INSTALL_BAD, text)
            if m:
                findings.append(finding("high", "install-script", "the install script runs %s as root when the package is installed" % m.group(1), name, line_of(text, m.start())))
            else:
                findings.append(finding("info", "install-script", "has an install script that runs as root inside the Arch environment", name))
    upstream = set()
    for u in info["base"].get("url", []) + [(meta or {}).get("URL") or ""]:
        h = host_of(u)
        if h:
            upstream.add(h)
            parts = h.split(".")
            if len(parts) > 2:
                upstream.add(".".join(parts[-2:]))
    sources = []
    for arch in (None, "x86_64"):
        key = "source" if arch is None else "source_" + arch
        srcs = info["base"].get(key, [])
        sums = {}
        for ck in CHECKSUM_KEYS:
            k = ck if arch is None else ck + "_" + arch
            if k in info["base"]:
                sums[ck] = info["base"][k]
        for i, s in enumerate(srcs):
            name, url = split_source(s)
            remote = "://" in url
            vcs = is_vcs(url)
            entry = {"source": s, "url": url if remote else None, "file": name or os.path.basename(url), "vcs": vcs, "remote": remote}
            have = {ck: v[i] for ck, v in sums.items() if i < len(v)}
            strong = [ck for ck in ("sha256sums", "sha512sums", "b2sums", "sha384sums", "sha224sums") if have.get(ck, "SKIP") != "SKIP"]
            entry["checksum"] = strong[0] if strong else ("weak" if any(v != "SKIP" for v in have.values()) else "SKIP")
            sources.append(entry)
    names = {s["file"] for s in sources}
    pgp = bool(info["base"].get("validpgpkeys"))
    sig_ext = (".sig", ".asc", ".gpg", ".sign")
    for entry in sources:
        if not entry["remote"]:
            continue
        url, fname, vcs = entry["url"], entry["file"], entry["vcs"]
        is_sig = fname.endswith(sig_ext)
        signed = pgp and any(fname + e in names for e in sig_ext)
        h = host_of(url)
        entry["domain"] = h
        entry["pgp_signed"] = signed
        skip = entry["checksum"] == "SKIP"
        if url.startswith("http://") or url.startswith("ftp://"):
            sev = "high" if skip and not signed and not is_sig else "medium"
            findings.append(finding(sev, "plain-http", "source fetched without TLS: %s%s" % (url, " (PGP-signed)" if signed else ""), "PKGBUILD"))
        if host_bad(h):
            findings.append(finding("high", "bad-host", "source from a paste/file-sharing/shortener host or a raw IP: %s" % h, "PKGBUILD"))
        elif not host_known(h, upstream):
            findings.append(finding("medium", "unusual-domain", "source from an unusual domain (not the upstream URL or a well-known forge): %s" % h, "PKGBUILD"))
        if not vcs and skip and not is_sig:
            if signed:
                findings.append(finding("low", "checksum-skip-signed", "checksum is SKIP for %s, which is checked with a PGP signature instead" % fname, "PKGBUILD"))
            else:
                findings.append(finding("high", "checksum-skip", "checksum is SKIP for a non-VCS download: %s" % fname, "PKGBUILD"))
        elif not vcs and entry["checksum"] == "weak":
            findings.append(finding("low", "weak-checksum", "only md5/sha1 checksums for %s" % fname, "PKGBUILD"))
        if vcs and "#commit=" not in url and "#tag=" not in url:
            findings.append(finding("info", "vcs-head", "builds the latest upstream commit of %s (not pinned)" % url, "PKGBUILD"))
    if info["base"].get("validpgpkeys"):
        findings.append(finding("info", "pgp", "source signatures checked against %d PGP key(s)" % len(info["base"]["validpgpkeys"])))
    if any(n.endswith("-bin") for n in info["pkgnames"]):
        findings.append(finding("info", "prebuilt", "installs prebuilt upstream binaries (-bin)"))
    findings += meta_findings(meta)
    findings += history_findings(hist)
    seen = set()
    uniq = []
    for f in findings:
        k = (f["id"], f.get("file"), f.get("line"), f["message"])
        if k not in seen:
            seen.add(k)
            uniq.append(f)
    uniq.sort(key=lambda f: -SEV[f["severity"]])
    return uniq, sources


def meta_out(m):
    return {
        "name": m.get("Name"), "base": m.get("PackageBase"), "version": m.get("Version"), "description": m.get("Description") or "",
        "url": m.get("URL"), "votes": m.get("NumVotes") or 0, "popularity": m.get("Popularity") or 0,
        "maintainer": m.get("Maintainer"), "submitter": m.get("Submitter"), "comaintainers": m.get("CoMaintainers") or [],
        "first_submitted": m.get("FirstSubmitted"), "last_modified": m.get("LastModified"), "out_of_date": m.get("OutOfDate"),
        "depends": m.get("Depends") or [], "makedepends": m.get("MakeDepends") or [], "checkdepends": m.get("CheckDepends") or [],
        "optdepends": m.get("OptDepends") or [], "provides": m.get("Provides") or [], "conflicts": m.get("Conflicts") or [],
        "license": m.get("License") or [], "keywords": m.get("Keywords") or [],
        "aur_url": "%s/packages/%s" % (base(), m.get("Name")),
    }


def review(name, commit=None, meta=None):
    if meta is None:
        meta = rpc_info([name]).get(name)
    if not meta:
        raise util.Fail("not-found", "%s is not in the AUR" % name, util.EXIT_NOTFOUND)
    pkgbase = meta["PackageBase"]
    hist = history(pkgbase)
    head = hist[0]["commit"]
    commit = commit or head
    files = snapshot(pkgbase, commit)
    srcinfo_text = files[".SRCINFO"].decode("utf-8", "replace")
    info = parse_srcinfo(srcinfo_text)
    if info["pkgbase"] != pkgbase:
        raise util.Fail("bad-snapshot", ".SRCINFO pkgbase %s does not match %s" % (info["pkgbase"], pkgbase))
    findings, sources = analyze(files, info, meta, hist)
    if commit != head:
        findings.insert(0, finding("info", "pinned-older", "reviewing commit %s; the AUR head is %s" % (commit[:12], head[:12])))
    return {
        "meta": meta,
        "package": meta_out(meta),
        "pkgbase": pkgbase,
        "commit": commit,
        "head": head,
        "history": hist,
        "files": files,
        "srcinfo": info,
        "srcinfo_text": srcinfo_text,
        "pkgbuild": files["PKGBUILD"].decode("utf-8", "replace"),
        "findings": findings,
        "sources": sources,
        "risk": risk(findings),
        "digest": digest(files),
        "version": full_version(info),
    }


def review_out(r, with_text=True):
    out = {
        "package": r["package"],
        "pkgbase": r["pkgbase"],
        "commit": r["commit"],
        "head": r["head"],
        "srcinfo_version": r["version"],
        "risk": r["risk"],
        "findings": r["findings"],
        "sources": r["sources"],
        "history": [{k: h[k] for k in ("commit", "author", "date", "subject")} for h in r["history"]],
        "files": [{"name": k, "size": len(v) if isinstance(v, bytes) else 0, "symlink": isinstance(v, tuple)} for k, v in sorted(r["files"].items())],
        "digest": r["digest"],
    }
    if with_text:
        out["pkgbuild"] = r["pkgbuild"]
        out["srcinfo"] = r["srcinfo_text"]
        out["install_scripts"] = {}
        for name in set(r["srcinfo"]["base"].get("install", []) + [v for p in r["srcinfo"]["pkgs"].values() for v in p.get("install", [])]):
            data = r["files"].get(name)
            if isinstance(data, bytes):
                out["install_scripts"][name] = data.decode("utf-8", "replace")
    return out


def write_tree(files, dest, uid):
    for rel, data in files.items():
        p = os.path.join(dest, rel)
        d = os.path.dirname(p)
        os.makedirs(d, exist_ok=True)
        if isinstance(data, tuple):
            continue
        with open(p, "wb") as f:
            f.write(data)
        os.chmod(p, 0o644 if not rel.endswith(".sh") else 0o755)
    for dp, dn, fn in os.walk(dest):
        os.chown(dp, uid, uid)
        for n in fn:
            os.chown(os.path.join(dp, n), uid, uid)
