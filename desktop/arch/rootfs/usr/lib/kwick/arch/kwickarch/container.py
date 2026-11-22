import base64
import hashlib
import os
import pwd
import grp
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time

from . import util

PASSTHROUGH_ENV = (
    "WAYLAND_DISPLAY", "DISPLAY", "XAUTHORITY", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "XDG_SESSION_TYPE",
    "XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "DESKTOP_SESSION", "LANG", "LANGUAGE", "LC_ALL", "LC_CTYPE", "LC_MESSAGES",
    "LC_TIME", "LC_NUMERIC", "LC_COLLATE", "LC_MONETARY", "LC_PAPER", "LC_MEASUREMENT", "TERM", "COLORTERM", "HOME", "USER",
    "LOGNAME", "SHELL", "PULSE_SERVER", "PIPEWIRE_REMOTE", "XDG_ACTIVATION_TOKEN", "DESKTOP_STARTUP_ID", "GDK_SCALE",
    "GDK_DPI_SCALE", "QT_SCALE_FACTOR", "QT_SCREEN_SCALE_FACTORS", "QT_AUTO_SCREEN_SCALE_FACTOR", "QT_ENABLE_HIGHDPI_SCALING",
    "XCURSOR_THEME", "XCURSOR_SIZE", "GTK_THEME", "EDITOR", "VISUAL", "TZ", "SSH_AUTH_SOCK", "MOZ_ENABLE_WAYLAND",
    "GTK_USE_PORTAL", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME", "XDG_CONFIG_DIRS",
)

HOST_SHARES = (("/usr/share/fonts", "usr/local/share/fonts"), ("/usr/share/icons", "usr/local/share/icons"), ("/usr/share/themes", "usr/local/share/themes"))


def enabled():
    return util.state().get("enabled") and os.path.isfile(os.path.join(util.ROOT, "usr/bin/pacman"))


def root_present():
    return os.path.isfile(os.path.join(util.ROOT, "usr/bin/pacman"))


def resolv():
    p = os.path.realpath("/etc/resolv.conf")
    return p if os.path.isfile(p) else None


def root_argv(cmd, net=True, ro=False, binds=(), env=None, user=None, cwd=None):
    a = ["bwrap", "--ro-bind" if ro else "--bind", util.ROOT, "/", "--dev", "/dev", "--perms", "1777", "--tmpfs", "/dev/shm", "--proc", "/proc",
         "--perms", "1777", "--tmpfs", "/tmp", "--tmpfs", "/run", "--unshare-pid", "--unshare-ipc", "--unshare-uts", "--unshare-cgroup-try",
         "--hostname", "kwick-arch", "--die-with-parent", "--new-session"]
    if net:
        r = resolv()
        if r:
            a += ["--ro-bind", r, "/etc/resolv.conf"]
    else:
        a += ["--unshare-net"]
    for src, dst, rw in binds:
        a += ["--bind" if rw else "--ro-bind", src, dst]
    a += ["--cap-add", "ALL"]
    a += ["--clearenv", "--setenv", "PATH", "/usr/local/sbin:/usr/local/bin:/usr/bin", "--setenv", "LANG", "C.UTF-8",
          "--setenv", "HOME", "/root" if user is None else "/build/home", "--setenv", "TERM", os.environ.get("TERM", "dumb")]
    for k, v in (env or {}).items():
        a += ["--setenv", k, v]
    if cwd:
        a += ["--chdir", cwd]
    if user is not None:
        uid = str(util.BUILDER_UID)
        a += ["--", "setpriv", "--reuid", uid, "--regid", uid, "--clear-groups", "--no-new-privs", "--inh-caps=-all",
              "--bounding-set=-all", "--"]
    else:
        a += ["--"]
    return a + list(cmd)


def in_root(cmd, check=True, capture=False, **kw):
    return util.run(root_argv(cmd, **kw), check=check, capture=capture)


def pacman_conf_ok():
    path = os.path.join(util.ROOT, "etc/pacman.conf")
    with open(path) as f:
        text = f.read()
    bad = []
    weak = {"Never", "PackageNever", "Optional", "PackageOptional", "TrustAll", "PackageTrustAll"}
    for m in re.finditer(r"(?m)^\s*(SigLevel|RemoteFileSigLevel)\s*=\s*(.*)$", text):
        if weak & set(m.group(2).split()):
            bad.append(m.group(0).strip())
    if bad:
        raise util.Fail("insecure-pacman-conf", "pacman.conf weakens signature checking (%s); kwick-arch keeps package signatures required" % "; ".join(bad))


def pacman(args, check=True, capture=False, net=True):
    pacman_conf_ok()
    quiet = [] if (sys.stdout.isatty() and not util.Out.json and not capture) else ["--noprogressbar"]
    return in_root(["pacman", "--noconfirm", "--color", "never"] + quiet + list(args), check=check, capture=capture, net=net)


def dearmor(path):
    with open(path, "rb") as f:
        data = f.read()
    if not data.lstrip().startswith(b"-----BEGIN PGP"):
        return data
    out = b""
    for block in re.findall(rb"-----BEGIN PGP PUBLIC KEY BLOCK-----(.*?)-----END PGP PUBLIC KEY BLOCK-----", data, re.S):
        lines = block.strip().splitlines()
        body = []
        started = False
        for ln in lines:
            ln = ln.strip()
            if not started:
                if ln == b"":
                    started = True
                elif b":" not in ln:
                    started = True
                    body.append(ln)
                continue
            if ln.startswith(b"="):
                break
            body.append(ln)
        out += base64.b64decode(b"".join(body))
    return out


def verify_signature(sig, path):
    keyring_src = util.conf("HOST_KEYRING")
    if not os.path.isfile(keyring_src):
        raise util.Fail("no-keyring", "%s is missing (install archlinux-keyring)" % keyring_src)
    if not shutil.which("gpgv"):
        raise util.Fail("no-gpgv", "gpgv is missing (install gpgv)")
    allowed = {k.upper() for k in util.conf_list("RELEASE_KEYS")}
    with tempfile.TemporaryDirectory() as td:
        kr = os.path.join(td, "arch.gpg")
        with open(kr, "wb") as f:
            f.write(dearmor(keyring_src))
        r = subprocess.run(["gpgv", "--homedir", td, "--status-fd", "1", "--keyring", kr, sig, path],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    fprs = set()
    for line in r.stdout.splitlines():
        p = line.split()
        if len(p) >= 3 and p[0] == "[GNUPG:]" and p[1] == "VALIDSIG":
            fprs.add(p[2].upper())
            if len(p) >= 12:
                fprs.add(p[11].upper())
    if r.returncode != 0 or not fprs:
        raise util.Fail("bad-signature", "the Arch bootstrap signature did not verify: " + (r.stderr.strip().splitlines() or ["no valid signature"])[-1])
    if not fprs & allowed:
        raise util.Fail("untrusted-signer", "the bootstrap is signed by %s, which is not a pinned Arch release key (RELEASE_KEYS)" % ", ".join(sorted(fprs)))
    return sorted(fprs & allowed)[0]


def fetch_bootstrap():
    base = util.conf("BOOTSTRAP_URL").rstrip("/")
    sums = util.http_get(base + "/sha256sums.txt")
    name = None
    digest = None
    for line in sums.splitlines():
        p = line.split()
        if len(p) == 2 and re.fullmatch(r"archlinux-bootstrap-\d{4}\.\d{2}\.\d{2}-x86_64\.tar\.zst", p[1]):
            digest, name = p
    if not name:
        raise util.Fail("no-bootstrap", "no dated bootstrap tarball listed in %s/sha256sums.txt" % base)
    d = os.path.join(util.CACHE, "bootstrap")
    os.makedirs(d, exist_ok=True)
    tar = os.path.join(d, name)
    sig = tar + ".sig"
    util.say("Downloading %s ..." % name)
    util.http_get(base + "/" + name + ".sig", dest=sig)
    if not os.path.isfile(tar) or sha256(tar) != digest:
        util.http_get(base + "/" + name, timeout=600, dest=tar)
    util.say("Verifying the PGP signature against Debian's archlinux-keyring ...")
    signer = verify_signature(sig, tar)
    if sha256(tar) != digest:
        raise util.Fail("bad-checksum", "sha256 of %s does not match the published sha256sums.txt" % name)
    return tar, name, signer, digest


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def extract(tar, dest):
    prefix = "root.x86_64/"

    def filt(member, path):
        if member.name.rstrip("/") == "root.x86_64":
            return None
        if not member.name.startswith(prefix):
            return None
        m = member.replace(name=member.name[len(prefix):], deep=False)
        if m.islnk() and m.linkname.startswith(prefix):
            m = m.replace(linkname=m.linkname[len(prefix):], deep=False)
        mode = m.mode
        m = tarfile.tar_filter(m, path)
        if m is not None and mode is not None and m.mode is not None and (mode & 0o1000) and m.isdir():
            m = m.replace(mode=m.mode | 0o1000, deep=False)
        return m

    p = subprocess.Popen(["zstd", "-dcq", tar], stdout=subprocess.PIPE)
    try:
        with tarfile.open(fileobj=p.stdout, mode="r|") as t:
            t.extractall(dest, numeric_owner=True, filter=filt)
    except (tarfile.TarError, OSError) as e:
        p.kill()
        raise util.Fail("extract-failed", "could not unpack the bootstrap: %s" % e)
    if p.wait() != 0:
        raise util.Fail("extract-failed", "zstd could not decompress the bootstrap")


def write(path, text, mode=0o644):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    os.chmod(path, mode)


def configure_root():
    r = util.ROOT
    servers = "".join("Server = %s\n" % m for m in util.conf_list("MIRRORS"))
    write(os.path.join(r, "etc/pacman.d/mirrorlist"), servers)
    pc = os.path.join(r, "etc/pacman.conf")
    with open(pc) as f:
        text = f.read()
    if "multilib" in util.conf_list("REPOS") and not re.search(r"(?m)^\[multilib\]", text):
        text = re.sub(r"(?m)^#\[multilib\]\n#Include = /etc/pacman.d/mirrorlist\n", "", text)
        text += "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n"
    text = re.sub(r"(?m)^#?\s*ParallelDownloads\s*=.*$", "ParallelDownloads = 5", text)
    write(pc, text)
    for rel in ("etc/localtime", "etc/machine-id", "etc/hostname", "etc/resolv.conf"):
        p = os.path.join(r, rel)
        if os.path.islink(p):
            os.unlink(p)
        if not os.path.exists(p):
            write(p, "")
    for _, rel in HOST_SHARES:
        os.makedirs(os.path.join(r, rel), exist_ok=True)
    os.makedirs(os.path.join(r, "build"), mode=0o755, exist_ok=True)
    os.makedirs(os.path.join(r, "check"), mode=0o755, exist_ok=True)
    os.makedirs(os.path.join(r, "usr/local/bin"), exist_ok=True)
    write(os.path.join(r, "usr/local/bin/xdg-open"), XDG_OPEN, 0o755)
    lang = os.environ.get("LANG", "en_US.UTF-8")
    gen = {"en_US.UTF-8 UTF-8"}
    try:
        with open("/etc/default/locale") as f:
            m = re.search(r"LANG=\"?([^\"\s]+)", f.read())
            if m:
                lang = m.group(1)
    except OSError:
        pass
    if re.fullmatch(r"[a-zA-Z_@]+\.UTF-8", lang):
        gen.add("%s UTF-8" % lang)
    write(os.path.join(r, "etc/locale.gen"), "".join(sorted(x + "\n" for x in gen)))
    write(os.path.join(r, "etc/locale.conf"), "LANG=%s\n" % (lang if lang.endswith("UTF-8") else "en_US.UTF-8"))


XDG_OPEN = """#!/bin/sh
for a; do
  case $a in
    *://*) u=$a ;;
    *) u=file://$(realpath -- "$a" 2>/dev/null || printf '%s' "$a") ;;
  esac
  gdbus call --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop \\
    --method org.freedesktop.portal.OpenURI.OpenURI "" "$u" "{}" >/dev/null || exit 1
done
"""


def ensure_builder():
    pw = os.path.join(util.ROOT, "etc/passwd")
    with open(pw) as f:
        if re.search(r"(?m)^%s:" % util.BUILDER, f.read()):
            return
    in_root(["groupadd", "-g", str(util.BUILDER_UID), util.BUILDER])
    in_root(["useradd", "-u", str(util.BUILDER_UID), "-g", str(util.BUILDER_UID), "-d", "/build/home", "-M", "-s", "/usr/bin/nologin", util.BUILDER])


def init_keyring():
    util.say("Initialising the pacman keyring (archlinux-keyring) ...")
    in_root(["pacman-key", "--init"], net=False)
    in_root(["pacman-key", "--populate", "archlinux"], net=False)


def bootstrap():
    tar, name, signer, digest = fetch_bootstrap()
    new = util.ROOT + ".new"
    if os.path.exists(new):
        shutil.rmtree(new)
    os.makedirs(new, mode=0o755)
    util.say("Unpacking the verified bootstrap ...")
    extract(tar, new)
    os.chmod(new, 0o755)
    if os.path.exists(util.ROOT):
        shutil.rmtree(util.ROOT)
    os.replace(new, util.ROOT)
    configure_root()
    init_keyring()
    in_root(["locale-gen"], net=False, check=False, capture=True)
    ensure_builder()
    if util.conf("KEEP_CACHE") != "1":
        try:
            os.unlink(tar)
        except OSError:
            pass
    return {"file": name, "sha256": digest, "signer": signer, "date": int(time.time())}


def host_user_files(rt):
    uid = os.getuid()
    gid = os.getgid()
    try:
        pw = pwd.getpwuid(uid)
    except KeyError:
        return None
    d = os.path.join(rt, "kwick-arch")
    os.makedirs(d, mode=0o700, exist_ok=True)
    with open(os.path.join(util.ROOT, "etc/passwd")) as f:
        lines = [ln for ln in f.read().splitlines() if ln and not ln.startswith(pw.pw_name + ":") and ln.split(":")[2:3] != [str(uid)]]
    lines.append("%s:x:%d:%d:%s:%s:/bin/bash" % (pw.pw_name, uid, gid, pw.pw_gecos, pw.pw_dir))
    write(os.path.join(d, "passwd"), "\n".join(lines) + "\n")
    try:
        gname = grp.getgrgid(gid).gr_name
    except KeyError:
        gname = pw.pw_name
    with open(os.path.join(util.ROOT, "etc/group")) as f:
        glines = [ln for ln in f.read().splitlines() if ln and ln.split(":")[2:3] != [str(gid)] and not ln.startswith(gname + ":")]
    glines.append("%s:x:%d:" % (gname, gid))
    write(os.path.join(d, "group"), "\n".join(glines) + "\n")
    return os.path.join(d, "passwd"), os.path.join(d, "group")


def user_argv(cmd, cwd=None):
    r = util.ROOT
    a = ["bwrap", "--ro-bind", os.path.join(r, "usr"), "/usr", "--symlink", "usr/bin", "/bin", "--symlink", "usr/bin", "/sbin",
         "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib", "/lib64", "--ro-bind", os.path.join(r, "etc"), "/etc",
         "--ro-bind", os.path.join(r, "var"), "/var", "--perms", "1777", "--tmpfs", "/var/tmp", "--dev-bind", "/dev", "/dev", "--proc", "/proc",
         "--ro-bind", "/sys", "/sys", "--bind", "/tmp", "/tmp", "--dir", "/run", "--dir", "/run/user"]
    if os.path.isdir(os.path.join(r, "opt")):
        a += ["--ro-bind", os.path.join(r, "opt"), "/opt"]
    rt = os.environ.get("XDG_RUNTIME_DIR")
    if rt and os.path.isdir(rt):
        a += ["--bind", rt, rt]
    for p in ("/run/dbus", "/run/media", "/media", "/mnt", "/run/pcscd", "/run/cups"):
        if os.path.exists(p):
            a += ["--bind" if p in ("/run/media", "/media", "/mnt") else "--ro-bind", p, p]
    home = os.path.expanduser("~")
    if os.path.isdir(home) and home != "/":
        a += ["--bind", home, home]
    for src, rel in HOST_SHARES:
        if os.path.isdir(src) and os.path.isdir(os.path.join(r, rel)):
            a += ["--ro-bind", src, "/" + rel]
    res = resolv()
    if res:
        a += ["--ro-bind", res, "/etc/resolv.conf"]
    for f in ("/etc/localtime", "/etc/machine-id", "/etc/hostname"):
        rp = os.path.realpath(f)
        if os.path.isfile(rp) and os.path.exists(os.path.join(r, f[1:])):
            a += ["--ro-bind", rp, f]
    if rt:
        files = host_user_files(rt)
        if files:
            a += ["--ro-bind", files[0], "/etc/passwd", "--ro-bind", files[1], "/etc/group"]
    a += ["--unshare-ipc", "--unshare-uts", "--hostname", os.uname().nodename, "--clearenv"]
    if not sys.stdin.isatty():
        a += ["--new-session"]
    env = {k: os.environ[k] for k in PASSTHROUGH_ENV if k in os.environ}
    env["PATH"] = "/usr/local/sbin:/usr/local/bin:/usr/bin"
    env["XDG_DATA_DIRS"] = "/usr/local/share:/usr/share"
    env["XDG_CONFIG_DIRS"] = "/etc/xdg"
    env["KWICK_ARCH"] = "1"
    env.setdefault("LANG", "en_US.UTF-8")
    for k, v in env.items():
        a += ["--setenv", k, v]
    a += ["--chdir", cwd or (os.getcwd() if os.path.isdir(os.getcwd()) else home)]
    return a + ["--"] + list(cmd)


def userns_ok():
    try:
        with open("/proc/sys/user/max_user_namespaces") as f:
            if int(f.read().strip() or 0) == 0:
                return False
    except OSError:
        return False
    try:
        with open("/proc/sys/kernel/unprivileged_userns_clone") as f:
            if f.read().strip() == "0":
                return False
    except OSError:
        pass
    return True
