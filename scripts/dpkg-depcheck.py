import re
import sys


def paragraphs(path):
    out, cur, key = [], {}, None
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip():
                if cur:
                    out.append(cur)
                cur, key = {}, None
                continue
            if line[0] in " \t" and key:
                cur[key] += "\n" + line
                continue
            key, _, val = line.partition(":")
            cur[key] = val.strip()
    if cur:
        out.append(cur)
    return out


def order(c):
    if c.isdigit():
        return 0
    if c.isalpha():
        return ord(c)
    if c == "~":
        return -1
    return ord(c) + 256


def verrevcmp(a, b):
    i = j = 0
    while i < len(a) or j < len(b):
        while (i < len(a) and not a[i].isdigit()) or (j < len(b) and not b[j].isdigit()):
            ac = order(a[i]) if i < len(a) else 0
            bc = order(b[j]) if j < len(b) else 0
            if ac != bc:
                return ac - bc
            i += 1
            j += 1
        while i < len(a) and a[i] == "0":
            i += 1
        while j < len(b) and b[j] == "0":
            j += 1
        first = 0
        while i < len(a) and a[i].isdigit() and j < len(b) and b[j].isdigit():
            if not first:
                first = ord(a[i]) - ord(b[j])
            i += 1
            j += 1
        if i < len(a) and a[i].isdigit():
            return 1
        if j < len(b) and b[j].isdigit():
            return -1
        if first:
            return first
    return 0


def split(v):
    epoch, rest = (v.split(":", 1) if ":" in v else ("0", v))
    up, rev = (rest.rsplit("-", 1) if "-" in rest else (rest, ""))
    return int(epoch or 0), up, rev


def vercmp(a, b):
    ea, ua, ra = split(a)
    eb, ub, rb = split(b)
    if ea != eb:
        return ea - eb
    return verrevcmp(ua, ub) or verrevcmp(ra, rb)


OPS = {"<<": lambda c: c < 0, "<=": lambda c: c <= 0, "=": lambda c: c == 0, ">=": lambda c: c >= 0, ">>": lambda c: c > 0}
REL = re.compile(r"([^\s(:]+)(?::\S+)?\s*(?:\(\s*(<<|<=|=|>=|>>)\s*([^)\s]+)\s*\))?")


def installed(p):
    st = p.get("Status", "").split()
    return len(st) == 3 and st[0] in ("install", "hold") and st[2] == "installed"


def main(status):
    paras = [p for p in paragraphs(status) if installed(p)]
    have = {}
    for p in paras:
        have.setdefault(p["Package"], []).append(p.get("Version", ""))
        for pv in filter(None, (x.strip() for x in p.get("Provides", "").replace("\n", " ").split(","))):
            m = REL.match(pv)
            if m:
                have.setdefault(m.group(1), []).append(m.group(3) if m.group(2) == "=" else None)

    def sat(alt):
        m = REL.match(alt.strip())
        if not m:
            return True
        name, op, ver = m.groups()
        for v in have.get(name, []):
            if not op:
                return True
            if v is not None and OPS[op](vercmp(v, ver)):
                return True
        return False

    bad = 0
    for p in paras:
        if p.get("X-Kwick-Base") == "yes":
            continue
        for fld in ("Pre-Depends", "Depends"):
            for group in filter(None, (g.strip() for g in p.get(fld, "").replace("\n", " ").split(","))):
                if not any(sat(a) for a in group.split("|")):
                    print("unmet: %s %s %s: %s" % (p["Package"], p.get("Version", ""), fld, group))
                    bad = 1
    return bad


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
