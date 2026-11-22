import json
import os
import time

from . import util
from .vercmp import vercmp

RANK = {"low": 1, "medium": 2, "unknown": 2, "high": 3, "critical": 4}
OPEN = {"Vulnerable", "Testing", "Unknown", "Fixed"}


def rank(sev):
    return RANK.get((sev or "unknown").lower(), 2)


def risk_of(advisories):
    top = max([rank(a["severity"]) for a in advisories] or [0])
    if top >= 3:
        return "high"
    if top == 2:
        return "medium"
    return "low"


class Tracker:
    def __init__(self, offline=False):
        self.offline = offline
        self.data = None
        self.fetched = 0
        self.error = None
        self.by_pkg = {}

    def path(self):
        return os.path.join(util.CACHE, "tracker.json")

    def user_path(self):
        home = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
        return os.path.join(home, "kwick-arch", "tracker.json")

    def load(self, force=False):
        if self.data is not None and not force:
            return self
        max_age = int(util.conf("TRACKER_MAX_AGE") or 21600)
        best = None
        for p in (self.path(), self.user_path()):
            try:
                st = os.stat(p)
            except OSError:
                continue
            if best is None or st.st_mtime > best[1]:
                best = (p, st.st_mtime)
        fresh = best and (time.time() - best[1] < max_age)
        if force or not fresh:
            if not self.offline:
                try:
                    raw = util.http_get(util.conf("TRACKER_URL"), timeout=60)
                    data = json.loads(raw)
                    if not isinstance(data, list):
                        raise ValueError("tracker data is not a list")
                    target = self.path() if util.is_root() else self.user_path()
                    try:
                        os.makedirs(os.path.dirname(target), exist_ok=True)
                        with open(target + ".new", "w") as f:
                            f.write(raw)
                        os.chmod(target + ".new", 0o644)
                        os.replace(target + ".new", target)
                        best = (target, time.time())
                    except OSError:
                        pass
                    self._index(data, time.time())
                    return self
                except (util.Fail, ValueError) as e:
                    self.error = getattr(e, "message", str(e))
        if best:
            try:
                with open(best[0]) as f:
                    self._index(json.load(f), best[1])
                return self
            except (OSError, ValueError) as e:
                self.error = str(e)
        raise util.Fail("tracker-unavailable", "the Arch Security Tracker could not be reached and there is no cached copy (%s); refusing to continue without a CVE check" % (self.error or "no data"))

    def _index(self, data, ts):
        self.data = data
        self.fetched = int(ts)
        self.by_pkg = {}
        for avg in data:
            for p in avg.get("packages") or []:
                self.by_pkg.setdefault(p, []).append(avg)

    def stale(self):
        return time.time() - self.fetched > 2 * int(util.conf("TRACKER_MAX_AGE") or 21600)

    def issues(self, name, version, base=None, strict=False):
        self.load()
        seen = set()
        out = []
        for key in (name, base):
            if not key:
                continue
            for avg in self.by_pkg.get(key, []):
                if avg["name"] in seen:
                    continue
                st = avg.get("status") or "Unknown"
                if st not in OPEN:
                    continue
                fixed = avg.get("fixed")
                if fixed and vercmp(version, fixed) >= 0:
                    continue
                if st == "Fixed" and not fixed:
                    continue
                if strict and avg.get("affected") and vercmp(version, avg["affected"]) < 0:
                    continue
                seen.add(avg["name"])
                out.append({
                    "avg": avg["name"],
                    "cves": list(avg.get("issues") or []),
                    "severity": (avg.get("severity") or "Unknown"),
                    "type": avg.get("type") or "unknown",
                    "status": st,
                    "affected": avg.get("affected"),
                    "fixed": fixed,
                    "url": "https://security.archlinux.org/" + avg["name"],
                })
        out.sort(key=lambda a: -rank(a["severity"]))
        return out


def cve_ids(advisories):
    ids = []
    for a in advisories:
        for c in a["cves"]:
            if c not in ids:
                ids.append(c)
    return ids


def threshold(key):
    return RANK.get(util.conf(key).lower(), 1)


def blocking(advisories, level):
    return [a for a in advisories if rank(a["severity"]) >= level]
