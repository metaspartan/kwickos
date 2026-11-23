import os
import re
import shutil
import subprocess

from . import safefs, util

SAFE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+@-]*$")
SIZES = ("scalable", "512x512", "256x256", "192x192", "128x128", "96x96", "64x64", "48x48", "32x32", "24x24", "16x16")
HOST_APP_DIRS = ("/usr/share/applications", "/usr/local/share/applications", "/var/lib/flatpak/exports/share/applications")


def resolve_icon(name):
    r = util.ROOT
    if not name:
        return name
    if name.startswith("/"):
        p = os.path.join(r, name.lstrip("/"))
        return p if os.path.isfile(p) else name
    for size in SIZES:
        for ext in ("svg", "png"):
            p = os.path.join(r, "usr/share/icons/hicolor", size, "apps", "%s.%s" % (name, ext))
            if os.path.isfile(p):
                return p
    for ext in ("svg", "png", "xpm"):
        p = os.path.join(r, "usr/share/pixmaps", "%s.%s" % (name, ext))
        if os.path.isfile(p):
            return p
    return name


def host_has(basename, ours):
    for d in HOST_APP_DIRS:
        p = os.path.join(d, basename)
        if os.path.exists(p) and p not in ours:
            return True
    return False


def rewrite_desktop(text, pkg, rename, wmclass=None):
    out = []
    section = None
    wm = wmclass
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            if section == "[Desktop Entry]":
                out.append("X-KwickOS-Arch-Package=%s" % pkg)
                if wm:
                    out.append("StartupWMClass=%s" % wm)
            section = s
            out.append(line)
            continue
        if "=" not in line or s.startswith("#"):
            out.append(line)
            continue
        k, v = line.split("=", 1)
        key = k.strip()
        if key == "Exec":
            out.append("Exec=%s run -- %s" % (util.SELF, v))
            continue
        if key in ("TryExec", "DBusActivatable", "X-KwickOS-Arch-Package"):
            continue
        if section == "[Desktop Entry]" and key == "StartupWMClass":
            wm = None
        if key == "Icon":
            out.append("Icon=%s" % resolve_icon(v.strip()))
            continue
        if rename and section == "[Desktop Entry]" and (key == "Name" or key.startswith("Name[")):
            out.append("%s=%s (Arch)" % (k, v))
            continue
        out.append(line)
    if section == "[Desktop Entry]":
        out.append("X-KwickOS-Arch-Package=%s" % pkg)
        if wm:
            out.append("StartupWMClass=%s" % wm)
    return "\n".join(out) + "\n"


def export_pkg(db, pkg, st):
    files = db.files(pkg)
    ours = set()
    for e in st["exports"].values():
        ours.update(e.get("desktop", []))
        ours.update(e.get("bin", []))
    made = {"desktop": [], "bin": []}
    for f in files:
        if f.startswith("usr/share/applications/") and f.endswith(".desktop") and f.count("/") == 3:
            base = os.path.basename(f)
            if not SAFE.match(base):
                continue
            try:
                text = safefs.read_text(util.ROOT, f, "replace")
            except OSError:
                continue
            rename = host_has(base, ours)
            target = os.path.join(util.EXPORT_APPS, ("kwick-arch-" + base) if rename else base)
            os.makedirs(util.EXPORT_APPS, exist_ok=True)
            tmp = target + ".kwick-arch.new"
            with open(tmp, "w", encoding="utf-8") as fh:
                fh.write(rewrite_desktop(text, pkg, rename, base[:-8] if rename else None))
            os.chmod(tmp, 0o644)
            os.replace(tmp, target)
            made["desktop"].append(target)
        elif f.startswith("usr/bin/") and f.count("/") == 2 and not f.endswith("/"):
            name = os.path.basename(f)
            if not SAFE.match(name):
                continue
            try:
                if safefs.lstat(util.ROOT, f) is None:
                    continue
            except OSError:
                continue
            os.makedirs(util.EXPORT_BIN, exist_ok=True)
            target = os.path.join(util.EXPORT_BIN, name)
            with open(target + ".new", "w") as fh:
                fh.write("#!/bin/sh\nexec %s run -- /usr/bin/%s \"$@\"\n" % (util.SELF, name))
            os.chmod(target + ".new", 0o755)
            os.replace(target + ".new", target)
            made["bin"].append(target)
    return made


def unexport(st, pkg):
    e = st["exports"].pop(pkg, None)
    if not e:
        return
    keep = set()
    for other in st["exports"].values():
        keep.update(other.get("desktop", []))
        keep.update(other.get("bin", []))
    for p in e.get("desktop", []) + e.get("bin", []):
        if p in keep:
            continue
        try:
            os.unlink(p)
        except OSError:
            pass


def refresh(db, st, only=None):
    local = db.local()
    requested = set(st.get("requested", []))
    want = {n for n, p in local.items() if p.get("explicit") and n in requested}
    for pkg in list(st["exports"].keys()):
        if pkg not in want:
            unexport(st, pkg)
    for pkg in sorted(want):
        if only is not None and pkg not in only and pkg in st["exports"]:
            continue
        old = st["exports"].get(pkg, {"desktop": [], "bin": []})
        made = export_pkg(db, pkg, st)
        for p in old.get("desktop", []) + old.get("bin", []):
            if p not in made["desktop"] and p not in made["bin"]:
                try:
                    os.unlink(p)
                except OSError:
                    pass
        if made["desktop"] or made["bin"]:
            st["exports"][pkg] = made
        else:
            st["exports"].pop(pkg, None)
    notify()


def remove_all(st):
    for pkg in list(st["exports"].keys()):
        unexport(st, pkg)
    if os.path.isdir(util.EXPORT_BIN):
        shutil.rmtree(util.EXPORT_BIN, ignore_errors=True)
    notify()


def notify():
    if shutil.which("update-desktop-database"):
        subprocess.run(["update-desktop-database", "-q", util.EXPORT_APPS], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def listing(st, pkg):
    e = st["exports"].get(pkg, {})
    return {"desktop": e.get("desktop", []), "bin": [os.path.basename(b) for b in e.get("bin", [])]}
