import fcntl
import json
import os
import platform
import shutil
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

VERSION_FILE = "/usr/lib/kwick/arch/VERSION"
CONF_FILE = os.environ.get("KWICK_ARCH_CONF", "/etc/kwick/arch.conf")
BASE = os.environ.get("KWICK_ARCH_DIR", "/var/lib/kwick/arch")
ROOT = os.path.join(BASE, "root")
CACHE = os.path.join(BASE, "cache")
BUILD = os.path.join(BASE, "build")
STATE_FILE = os.path.join(BASE, "state.json")
CHECK_FILE = os.path.join(BASE, "check.json")
LOCK_FILE = os.path.join(BASE, ".lock")
EXPORT_APPS = os.environ.get("KWICK_ARCH_APPS", "/usr/local/share/applications")
EXPORT_BIN = os.environ.get("KWICK_ARCH_BIN", "/usr/local/lib/kwick-arch/bin")
SELF = "/usr/bin/kwick-arch"
BUILDER = "kwickbuild"
BUILDER_UID = 64990

DEFAULTS = {
    "MIRRORS": "https://geo.mirror.pkgbuild.com/$repo/os/$arch https://mirror.rackspace.com/archlinux/$repo/os/$arch https://mirrors.kernel.org/archlinux/$repo/os/$arch",
    "BOOTSTRAP_URL": "https://geo.mirror.pkgbuild.com/iso/latest",
    "RELEASE_KEYS": "3E80CA1A8B89F69CBA57D98A76A5EF9054449A5C",
    "HOST_KEYRING": "/usr/share/keyrings/archlinux.gpg",
    "TRACKER_URL": "https://security.archlinux.org/issues/all.json",
    "AUR_URL": "https://aur.archlinux.org",
    "REPOS": "core extra multilib",
    "ENABLE_PACKAGES": "mesa",
    "CVE_BLOCK_TARGET": "low",
    "CVE_BLOCK_DEPS": "high",
    "TRACKER_MAX_AGE": "21600",
    "KEEP_CACHE": "0",
    "AUR_NETWORK_BUILD": "0",
}

EXIT_ERROR = 1
EXIT_USAGE = 2
EXIT_CONFIRM = 3
EXIT_VULNERABLE = 4
EXIT_RISK = 5
EXIT_DISABLED = 6
EXIT_UNSUPPORTED = 7
EXIT_NOTFOUND = 8


class Fail(Exception):
    def __init__(self, code, message, status=EXIT_ERROR, **extra):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status
        self.extra = extra


def version():
    try:
        with open(VERSION_FILE) as f:
            return f.read().strip()
    except OSError:
        return "0"


_conf = None


def conf(key):
    global _conf
    if _conf is None:
        _conf = dict(DEFAULTS)
        try:
            with open(CONF_FILE) as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    k, v = line.split("=", 1)
                    v = v.strip()
                    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                        v = v[1:-1]
                    _conf[k.strip()] = v
        except OSError:
            pass
    return _conf.get(key, "")


def conf_list(key):
    return conf(key).split()


class Out:
    json = False
    quiet = False


def say(*a):
    if Out.json:
        print(*a, file=sys.stderr, flush=True)
    elif not Out.quiet:
        print(*a, flush=True)


def warn(msg):
    print("kwick-arch: " + msg, file=sys.stderr, flush=True)


def emit(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False, sort_keys=False) + "\n")
    sys.stdout.flush()


def is_root():
    return os.geteuid() == 0


def machine():
    return platform.machine()


def supported():
    m = machine()
    if m == "x86_64":
        return True, ""
    if m == "aarch64":
        return False, "Arch Linux publishes x86_64 only. Arch Linux ARM (aarch64) is a separate project without the Arch Security Tracker or a release key in Debian's archlinux-keyring, so kwick-arch does not support it."
    return False, "Arch Linux has no official port for %s; kwick-arch supports x86_64 only." % m


def elevate(argv):
    if is_root():
        return
    exe = SELF if os.path.exists(SELF) else os.path.abspath(sys.argv[0])
    tty = sys.stdin.isatty()
    if (not tty or not shutil.which("sudo")) and shutil.which("pkexec"):
        os.execvp("pkexec", ["pkexec", exe] + argv)
    if shutil.which("sudo"):
        os.execvp("sudo", ["sudo", exe] + argv)
    raise Fail("needs-root", "this command needs root (try sudo)", EXIT_ERROR)


def read_json(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, obj, mode=0o644):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".new"
    with open(tmp, "w") as f:
        json.dump(obj, f, indent=1, sort_keys=True)
        f.write("\n")
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def state():
    s = read_json(STATE_FILE, {})
    s.setdefault("enabled", False)
    s.setdefault("exports", {})
    s.setdefault("aur", {})
    return s


def save_state(s):
    write_json(STATE_FILE, s)


class Lock:
    def __enter__(self):
        os.makedirs(BASE, exist_ok=True)
        self.f = open(LOCK_FILE, "w")
        try:
            fcntl.flock(self.f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise Fail("busy", "another kwick-arch task is running", EXIT_ERROR)
        return self

    def __exit__(self, *a):
        fcntl.flock(self.f, fcntl.LOCK_UN)
        self.f.close()


_ctx = None


def ssl_ctx():
    global _ctx
    if _ctx is None:
        _ctx = ssl.create_default_context()
        _ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    return _ctx


def http_get(url, timeout=60, binary=False, dest=None):
    if not url.startswith("https://"):
        raise Fail("insecure-url", "refusing a non-HTTPS URL: " + url)
    req = urllib.request.Request(url, headers={"User-Agent": "kwick-arch/" + version()})
    last = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=timeout, context=ssl_ctx()) as r:
                if r.geturl() and not r.geturl().startswith("https://"):
                    raise Fail("insecure-url", "redirected to a non-HTTPS URL: " + r.geturl())
                if dest:
                    tmp = dest + ".part"
                    with open(tmp, "wb") as f:
                        shutil.copyfileobj(r, f, 1 << 20)
                    os.replace(tmp, dest)
                    return dest
                data = r.read()
                return data if binary else data.decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise Fail("not-found", "%s: not found" % url, EXIT_NOTFOUND)
            last = e
        except (urllib.error.URLError, OSError, TimeoutError) as e:
            last = e
        time.sleep(1 + attempt)
    raise Fail("network", "download failed: %s (%s)" % (url, last))


def http_json(url, timeout=60):
    try:
        return json.loads(http_get(url, timeout))
    except ValueError:
        raise Fail("bad-response", "unexpected response from " + url)


def quote(s):
    return urllib.parse.quote(s, safe="")


def run(cmd, check=True, capture=False, env=None, input=None):
    r = subprocess.run(cmd, check=False, env=env, input=input,
                       stdout=subprocess.PIPE if capture else (sys.stderr if Out.json else None),
                       stderr=subprocess.PIPE if capture else None, text=True)
    if check and r.returncode != 0:
        detail = (r.stderr or "").strip().splitlines()[-1:] if capture else []
        raise Fail("command-failed", "%s failed (exit %d)%s" % (os.path.basename(cmd[0]), r.returncode, (": " + detail[0]) if detail else ""))
    return r


def confirm(prompt, assume_yes):
    if assume_yes:
        return True
    if not sys.stdin.isatty():
        return False
    try:
        a = input(prompt + " [y/N] ").strip().lower()
    except EOFError:
        return False
    return a in ("y", "yes")


def dir_size(path):
    total = 0
    for dp, dn, fn in os.walk(path):
        for n in fn:
            try:
                st = os.lstat(os.path.join(dp, n))
                total += st.st_blocks * 512
            except OSError:
                pass
    return total
