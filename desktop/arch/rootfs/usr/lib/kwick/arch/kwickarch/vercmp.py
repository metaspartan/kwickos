def _rpmvercmp(a, b):
    if a == b:
        return 0
    la, lb = len(a), len(b)
    one = two = 0
    p1 = p2 = 0
    isnum = False
    while one < la and two < lb:
        while one < la and not a[one].isalnum():
            one += 1
        while two < lb and not b[two].isalnum():
            two += 1
        if one >= la or two >= lb:
            break
        if (one - p1) != (two - p2):
            return -1 if (one - p1) < (two - p2) else 1
        p1, p2 = one, two
        if a[p1].isdigit():
            while p1 < la and a[p1].isdigit():
                p1 += 1
            while p2 < lb and b[p2].isdigit():
                p2 += 1
            isnum = True
        else:
            while p1 < la and a[p1].isalpha():
                p1 += 1
            while p2 < lb and b[p2].isalpha():
                p2 += 1
            isnum = False
        s1, s2 = a[one:p1], b[two:p2]
        if not s1:
            return -1
        if not s2:
            return 1 if isnum else -1
        if isnum:
            s1 = s1.lstrip("0")
            s2 = s2.lstrip("0")
            if len(s1) != len(s2):
                return 1 if len(s1) > len(s2) else -1
        if s1 != s2:
            return 1 if s1 > s2 else -1
        one, two = p1, p2
    if one >= la and two >= lb:
        return 0
    if (one >= la and not (two < lb and b[two].isalpha())) or (one < la and a[one].isalpha()):
        return -1
    return 1


def _evr(s):
    epoch = "0"
    i = 0
    while i < len(s) and s[i].isdigit():
        i += 1
    rest = s
    if i < len(s) and s[i] == ":":
        epoch = s[:i] or "0"
        rest = s[i + 1:]
    rel = None
    if "-" in rest:
        rest, rel = rest.rsplit("-", 1)
    return epoch, rest, rel


def vercmp(a, b):
    if a == b:
        return 0
    e1, v1, r1 = _evr(a)
    e2, v2, r2 = _evr(b)
    ret = _rpmvercmp(e1, e2)
    if ret == 0:
        ret = _rpmvercmp(v1, v2)
        if ret == 0 and r1 and r2:
            ret = _rpmvercmp(r1, r2)
    return ret


def satisfies(have, op, want):
    c = vercmp(have, want)
    return {"=": c == 0, ">=": c >= 0, "<=": c <= 0, ">": c > 0, "<": c < 0}.get(op, True)


def split_dep(dep):
    for op in (">=", "<=", "=", ">", "<"):
        i = dep.find(op)
        if i > 0:
            return dep[:i], op, dep[i + len(op):]
    return dep, None, None
