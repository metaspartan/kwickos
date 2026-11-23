#!/usr/bin/env python3
import os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
BASE = os.path.join(ROOT, "desktop", "rootfs", "usr", "share", "kwick")
MEMBER = re.compile(r"^\s*(?:readonly\s+|default\s+|required\s+)*(?:property\s+(?:var|bool|int|real|double|string|color|url|list<\w+>|[A-Z]\w*)\s+(\w+)|function\s+(\w+)\s*\(|signal\s+(\w+)|property\s+alias\s+(\w+)|id:\s*(\w+))", re.M)
QT_OBJECT = {"objectName", "toString", "destroy"}


def members(path):
    text = open(path, encoding="utf-8").read()
    names = set(QT_OBJECT)
    for m in MEMBER.finditer(text):
        n = next(g for g in m.groups() if g)
        names.add(n)
        names.add("on" + n[0].upper() + n[1:] + "Changed")
    return names


def strip(text):
    text = re.sub(r"//[^\n]*", "", text)
    return re.sub(r'"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'', '""', text)


fail = 0
for d in sorted(os.listdir(BASE)):
    qmldir = os.path.join(BASE, d, "qmldir")
    if not os.path.isfile(qmldir):
        continue
    singletons = {}
    for line in open(qmldir, encoding="utf-8"):
        p = line.split()
        if len(p) == 4 and p[0] == "singleton":
            singletons[p[1]] = members(os.path.join(BASE, d, p[3]))
    if not singletons:
        continue
    for f in sorted(os.listdir(os.path.join(BASE, d))):
        if not f.endswith(".qml"):
            continue
        text = strip(open(os.path.join(BASE, d, f), encoding="utf-8").read())
        for name, have in singletons.items():
            for m in re.finditer(r"(?<![\w.])%s\.(\w+)" % name, text):
                if m.group(1) not in have:
                    line = text.count("\n", 0, m.start()) + 1
                    print("FAIL  %s/%s:%d: %s.%s is not defined in %s.qml" % (d, f, line, name, m.group(1), name))
                    fail = 1
print("ok" if not fail else "qml singleton references are broken")
sys.exit(fail)
