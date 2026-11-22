import io
import lzma
import os
import subprocess
import tarfile

from . import util
from .vercmp import satisfies, split_dep

LIST_KEYS = {"DEPENDS", "OPTDEPENDS", "MAKEDEPENDS", "CHECKDEPENDS", "PROVIDES", "CONFLICTS", "REPLACES", "GROUPS", "LICENSE", "FILES", "BACKUP", "VALIDATION", "XDATA"}


def parse_desc(text):
    out = {}
    key = None
    for line in text.split("\n"):
        if line.startswith("%") and line.endswith("%") and len(line) > 2:
            key = line[1:-1]
            out[key] = [] if key in LIST_KEYS else ""
            continue
        if key is None:
            continue
        if line == "":
            if key not in LIST_KEYS:
                key = None
            continue
        if key in LIST_KEYS:
            out[key].append(line)
        elif out[key]:
            out[key] += "\n" + line
        else:
            out[key] = line
    return out


def _open_db(path):
    with open(path, "rb") as f:
        head = f.read(6)
    if head[:4] == b"\x28\xb5\x2f\xfd":
        data = subprocess.run(["zstd", "-dcq", path], stdout=subprocess.PIPE, check=True).stdout
        return tarfile.open(fileobj=io.BytesIO(data), mode="r:")
    if head[:6] == b"\xfd7zXZ\x00":
        return tarfile.open(fileobj=io.BytesIO(lzma.open(path).read()), mode="r:")
    return tarfile.open(path, mode="r:*")


def _pkg(d, repo):
    return {
        "name": d.get("NAME", ""),
        "base": d.get("BASE") or d.get("NAME", ""),
        "version": d.get("VERSION", ""),
        "description": d.get("DESC", ""),
        "url": d.get("URL", ""),
        "repo": repo,
        "csize": int(d.get("CSIZE") or 0),
        "isize": int(d.get("ISIZE") or d.get("SIZE") or 0),
        "builddate": int(d.get("BUILDDATE") or 0),
        "licenses": d.get("LICENSE", []),
        "depends": d.get("DEPENDS", []),
        "optdepends": d.get("OPTDEPENDS", []),
        "provides": d.get("PROVIDES", []),
        "conflicts": d.get("CONFLICTS", []),
        "replaces": d.get("REPLACES", []),
        "groups": d.get("GROUPS", []),
        "packager": d.get("PACKAGER", ""),
    }


def _read_sync(repo, dbpath, temp):
    path = os.path.join(dbpath, "sync", repo + ".db")
    try:
        mtime = os.stat(path).st_mtime_ns
    except OSError:
        return []
    idx = os.path.join(util.CACHE, "index-%s.json" % repo)
    if not temp:
        cached = util.read_json(idx)
        if cached and cached.get("mtime") == mtime:
            return cached["packages"]
    pkgs = []
    with _open_db(path) as t:
        for m in t:
            if not m.isfile() or not m.name.endswith("/desc"):
                continue
            pkgs.append(_pkg(parse_desc(t.extractfile(m).read().decode("utf-8", "replace")), repo))
    if util.is_root() and not temp:
        try:
            util.write_json(idx, {"mtime": mtime, "packages": pkgs})
        except OSError:
            pass
    return pkgs


class DB:
    def __init__(self, root=None, dbpath=None):
        self.root = root or util.ROOT
        self.dbpath = dbpath or os.path.join(self.root, "var/lib/pacman")
        self.temp = dbpath is not None
        self._sync = None
        self._local = None
        self._byname = None

    def repos(self):
        return util.conf_list("REPOS")

    def sync(self):
        if self._sync is None:
            self._sync = []
            for r in self.repos():
                self._sync.extend(_read_sync(r, self.dbpath, self.temp))
        return self._sync

    def sync_by_name(self):
        if self._byname is None:
            self._byname = {}
            for p in self.sync():
                self._byname.setdefault(p["name"], p)
        return self._byname

    def local(self):
        if self._local is None:
            self._local = {}
            d = os.path.join(self.root, "var/lib/pacman/local")
            try:
                entries = os.listdir(d)
            except OSError:
                entries = []
            for e in entries:
                fp = os.path.join(d, e, "desc")
                try:
                    with open(fp, encoding="utf-8", errors="replace") as f:
                        desc = parse_desc(f.read())
                except OSError:
                    continue
                p = _pkg(desc, "local")
                p["explicit"] = desc.get("REASON", "0") != "1"
                p["installdate"] = int(desc.get("INSTALLDATE") or 0)
                p["dir"] = e
                self._local[p["name"]] = p
        return self._local

    def files(self, name):
        p = self.local().get(name)
        if not p:
            return []
        try:
            with open(os.path.join(self.root, "var/lib/pacman/local", p["dir"], "files"), encoding="utf-8", errors="replace") as f:
                return parse_desc(f.read()).get("FILES", [])
        except OSError:
            return []

    def provider(self, dep, pool):
        name, op, ver = split_dep(dep)
        for p in pool:
            if p["name"] == name and (not op or satisfies(p["version"], op, ver)):
                return p
        for p in pool:
            for pr in p.get("provides", []):
                pn, _, pv = split_dep(pr)
                if pn == name and (not op or (pv and satisfies(pv, op, ver))):
                    return p
        return None

    def installed_satisfies(self, dep):
        return self.provider(dep, list(self.local().values()))

    def repo_satisfies(self, dep):
        name = split_dep(dep)[0]
        byname = self.sync_by_name()
        if name in byname:
            p = self.provider(dep, [byname[name]])
            if p:
                return p
        return self.provider(dep, self.sync())

    def groups(self, name):
        return [p for p in self.sync() if name in p.get("groups", [])]

    def foreign(self):
        sync = self.sync_by_name()
        return [p for n, p in self.local().items() if n not in sync]
