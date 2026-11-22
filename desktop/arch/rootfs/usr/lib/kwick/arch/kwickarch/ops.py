import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

from . import aur, container, exports, tracker, util
from .pacdb import DB
from .vercmp import split_dep, vercmp

TOOLCHAIN = ["base-devel", "git"]


def require_enabled():
    ok, why = util.supported()
    if not ok:
        raise util.Fail("unsupported", why, util.EXIT_UNSUPPORTED)
    if not container.enabled():
        raise util.Fail("disabled", "the Arch environment is not enabled (run: kwick-arch enable)", util.EXIT_DISABLED)


def clean_cache():
    if util.conf("KEEP_CACHE") == "1":
        return
    for p in glob.glob(os.path.join(util.ROOT, "var/cache/pacman/pkg/*")):
        try:
            if os.path.isfile(p):
                os.unlink(p)
        except OSError:
            pass


def plan(targets, upgrade=True, asdeps=False):
    args = ["-S" + ("u" if upgrade else ""), "--needed", "--print", "--print-format", "%n %v %r"] + list(targets)
    r = container.pacman(args, capture=True, check=False)
    if r.returncode != 0:
        msg = [ln for ln in (r.stderr or "").splitlines() if ln.startswith("error:")] or (r.stderr or "").strip().splitlines()[-1:]
        m = re.search(r"target not found: (\S+)", r.stderr or "")
        if m:
            raise util.Fail("not-found", "%s is not in the Arch repositories (core, extra, multilib)%s" % (m.group(1), "; try --aur" if not asdeps else ""), util.EXIT_NOTFOUND, package=m.group(1))
        raise util.Fail("plan-failed", "pacman could not plan the transaction: " + (msg[0] if msg else "unknown error"))
    out = []
    for line in r.stdout.splitlines():
        p = line.split()
        if len(p) == 3 and not line.startswith(("::", "warning", "error")):
            out.append({"name": p[0], "version": p[1], "repo": p[2]})
    return out


def gate(entries, targets, db, trk, allow):
    local = db.local()
    sync = db.sync_by_name()
    tlevel = tracker.threshold("CVE_BLOCK_TARGET")
    dlevel = tracker.threshold("CVE_BLOCK_DEPS")
    tnames = set(targets)
    for t in targets:
        for p in db.groups(t):
            tnames.add(p["name"])
        sp = db.repo_satisfies(t) if t not in sync else sync[t]
        if sp:
            tnames.add(sp["name"])
    blocked = []
    warnings = []
    for e in entries:
        name = e["name"]
        sp = sync.get(name, {})
        b = sp.get("base") or name
        old = local.get(name)
        e["from"] = old["version"] if old else None
        adv = trk.issues(name, e["version"], b)
        e["advisories"] = adv
        e["cve"] = tracker.cve_ids(adv)
        if old:
            prev = trk.issues(name, old["version"], old.get("base") or b)
            prev_ids = {a["avg"] for a in trk.issues(name, old["version"], old.get("base") or b, strict=True)}
            new = [a for a in adv if a["avg"] not in prev_ids]
            e["fixes"] = tracker.cve_ids([a for a in prev if a["avg"] not in {x["avg"] for x in adv}])
            e["role"] = "target" if name in tnames else "upgrade"
            level = tlevel if (name in tnames or old.get("explicit")) else dlevel
            hits = tracker.blocking(new, level)
        else:
            e["fixes"] = []
            e["role"] = "target" if name in tnames else "dependency"
            level = tlevel if name in tnames else dlevel
            hits = tracker.blocking(adv, level)
        e["risk"] = tracker.risk_of(adv)
        e["blocked"] = bool(hits) and not allow
        if hits:
            blocked.append(e)
        elif adv:
            warnings.append(e)
    return blocked, warnings


def describe(e):
    parts = []
    for a in e["advisories"]:
        parts.append("%s %s %s (%s)" % (a["avg"], a["severity"], a["type"], ", ".join(a["cves"][:4]) + (" ..." if len(a["cves"]) > 4 else "")))
    return "; ".join(parts)


def show_plan(entries, blocked, warnings):
    for e in entries:
        arrow = ("%s -> " % e["from"]) if e.get("from") else ""
        flag = " [BLOCKED: open CVEs]" if e in blocked else (" [known CVEs]" if e["advisories"] else "")
        util.say("  %-34s %s%s  (%s, %s)%s" % (e["name"], arrow, e["version"], e["repo"], e["role"], flag))
    for e in blocked + warnings:
        util.say("  %s %s: %s" % ("refused" if e in blocked else "warning", e["name"], describe(e)))


def entry_out(e):
    return {k: e.get(k) for k in ("name", "version", "from", "repo", "role", "cve", "fixes", "advisories", "risk", "blocked")}


def vulnerable_fail(blocked, entries, what):
    names = ", ".join("%s %s" % (e["name"], e["version"]) for e in blocked)
    return util.Fail("vulnerable", "%s refused: %s %s open security issues in the Arch Security Tracker (%s). Re-run with --allow-vulnerable to install anyway." % (
        what, names, "has" if len(blocked) == 1 else "have", "; ".join(describe(e) for e in blocked)), util.EXIT_VULNERABLE,
        blocked=[entry_out(e) for e in blocked], transaction=[entry_out(e) for e in entries])


def refresh_db():
    util.say("Synchronising package databases ...")
    container.pacman(["-Sy"])


def transact(targets, yes, allow, asdeps=False, what="install", refresh=True):
    if refresh:
        refresh_db()
    db = DB()
    trk = tracker.Tracker().load()
    entries = plan(targets, asdeps=asdeps)
    if not entries:
        return [], [], db
    blocked, warnings = gate(entries, [] if asdeps else targets, db, trk, allow)
    if not util.Out.json or sys.stdin.isatty():
        show_plan(entries, blocked, warnings)
    if blocked and not allow:
        raise vulnerable_fail(blocked, entries, "installation" if what == "install" else what)
    if not util.confirm("Proceed with %d package(s)?" % len(entries), yes):
        raise util.Fail("confirm", "confirmation required (pass --yes)", util.EXIT_CONFIRM, transaction=[entry_out(e) for e in entries])
    args = ["-Su", "--needed"] + (["--asdeps"] if asdeps else []) + list(targets)
    container.pacman(args)
    return entries, warnings, db


def enable(yes):
    ok, why = util.supported()
    if not ok:
        raise util.Fail("unsupported", why, util.EXIT_UNSUPPORTED)
    if not shutil.which("bwrap"):
        raise util.Fail("no-bwrap", "bubblewrap (bwrap) is missing")
    st = util.state()
    with util.Lock():
        if not container.root_present():
            st["bootstrap"] = container.bootstrap()
            util.save_state(st)
        container.configure_root()
        container.ensure_builder()
        tracker.Tracker().load()
        refresh_db()
        util.say("Updating archlinux-keyring first ...")
        container.pacman(["-S", "--needed", "archlinux-keyring"])
        util.say("Bringing the bootstrap up to date ...")
        transact([], True, True, what="upgrade", refresh=False)
        extra = [p for p in util.conf_list("ENABLE_PACKAGES") if p]
        if extra:
            util.say("Installing integration packages: %s" % " ".join(extra))
            transact(extra, True, False, asdeps=True, refresh=False)
        container.in_root(["locale-gen"], net=False, check=False, capture=True)
        st = util.state()
        st["enabled"] = True
        st["enabled_at"] = int(time.time())
        db = DB()
        exports.refresh(db, st)
        util.save_state(st)
        clean_cache()
    return {"ok": True, "enabled": True, "bootstrap": st.get("bootstrap"), "root": util.ROOT}


def disable(purge):
    st = util.state()
    with util.Lock():
        exports.remove_all(st)
        st["enabled"] = False
        st["exports"] = {}
        if purge:
            for p in (util.ROOT, util.ROOT + ".new", util.BUILD, util.CACHE, util.CHECK_FILE):
                if os.path.isdir(p):
                    shutil.rmtree(p, ignore_errors=True)
                elif os.path.exists(p):
                    os.unlink(p)
            st = {"enabled": False, "exports": {}, "aur": {}}
        util.save_state(st)
    return {"ok": True, "enabled": False, "purged": bool(purge)}


def add_requested(st, names):
    st["requested"] = sorted(set(st.get("requested", [])) | set(names))


def install_repo(targets, yes, allow):
    require_enabled()
    with util.Lock():
        entries, warnings, db = transact(targets, yes, allow)
        st = util.state()
        db = DB()
        names = {e["name"] for e in entries if e.get("role") == "target"} | {t for t in targets if t in db.local()}
        add_requested(st, names)
        exports.refresh(db, st, only=names)
        util.save_state(st)
        clean_cache()
        installed = sorted(n for n in names if n in db.local())
    return {"ok": True, "installed": installed, "transaction": [entry_out(e) for e in entries],
            "warnings": [entry_out(e) for e in warnings], "exports": {n: exports.listing(st, n) for n in installed}}


def remove(targets, yes):
    require_enabled()
    with util.Lock():
        db = DB()
        missing = [t for t in targets if t not in db.local()]
        if missing:
            raise util.Fail("not-installed", "not installed in the Arch environment: " + ", ".join(missing), util.EXIT_NOTFOUND)
        r = container.pacman(["-Rns"] + list(targets), check=False, capture=True)
        if r.returncode != 0:
            err = [ln for ln in (r.stderr or "").splitlines() if ln.startswith(("error:", ":: "))]
            raise util.Fail("remove-failed", "pacman could not remove %s: %s" % (", ".join(targets), " ".join(err) or r.stderr.strip()))
        if util.Out.json:
            sys.stderr.write(r.stdout)
        else:
            sys.stdout.write(r.stdout)
        st = util.state()
        for t in targets:
            exports.unexport(st, t)
            st["aur"].pop(t, None)
        st["requested"] = [n for n in st.get("requested", []) if n not in targets]
        exports.refresh(DB(), st, only=set())
        util.save_state(st)
    return {"ok": True, "removed": list(targets)}


def temp_sync():
    td = tempfile.mkdtemp(prefix="kwick-arch-check-")
    os.chmod(td, 0o755)
    os.symlink("/var/lib/pacman/local", os.path.join(td, "local"))
    os.makedirs(os.path.join(td, "sync"))
    for f in glob.glob(os.path.join(util.ROOT, "var/lib/pacman/sync/*.db")):
        shutil.copy2(f, os.path.join(td, "sync"))
    if util.is_root():
        argv = container.root_argv(["pacman", "-Sy", "--dbpath", "/check", "--logfile", "/dev/null", "--noconfirm", "--color", "never", "--noprogressbar"],
                                   binds=[(td, "/check", True)])
    else:
        argv = ["bwrap", "--unshare-user", "--uid", "0", "--gid", "0"] + container.user_argv(
            ["pacman", "-Sy", "--dbpath", "/check", "--logfile", "/dev/null", "--noconfirm", "--color", "never", "--noprogressbar", "--disable-sandbox"])[1:]
        i = argv.index("--")
        argv[i:i] = ["--bind", td, "/check"]
    r = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if r.returncode != 0:
        shutil.rmtree(td, ignore_errors=True)
        raise util.Fail("check-failed", "could not refresh the package databases: " + ((r.stderr or "").strip().splitlines() or ["?"])[-1])
    return td


def check(offline_ok=True):
    require_enabled()
    td = temp_sync()
    try:
        db = DB(dbpath=td)
        trk = tracker.Tracker().load()
        local = db.local()
        sync = db.sync_by_name()
        updates = []
        for name, lp in sorted(local.items()):
            sp = sync.get(name)
            if not sp or vercmp(sp["version"], lp["version"]) <= 0:
                continue
            new = trk.issues(name, sp["version"], sp.get("base"))
            old = trk.issues(name, lp["version"], lp.get("base"))
            old_ids = {a["avg"] for a in old}
            new_ids = {a["avg"] for a in new}
            level = tracker.threshold("CVE_BLOCK_TARGET") if lp.get("explicit") else tracker.threshold("CVE_BLOCK_DEPS")
            strict_ids = {a["avg"] for a in trk.issues(name, lp["version"], lp.get("base"), strict=True)}
            intro = tracker.blocking([a for a in new if a["avg"] not in strict_ids], level)
            updates.append({"name": name, "from": lp["version"], "to": sp["version"], "repo": sp["repo"], "size": sp["csize"],
                            "description": sp["description"], "cve": tracker.cve_ids(new),
                            "fixes": tracker.cve_ids([a for a in old if a["avg"] not in new_ids]), "security": bool(old_ids - new_ids),
                            "blocked": bool(intro), "advisories": new})
        vulnerable = []
        for name, lp in sorted(local.items()):
            adv = trk.issues(name, lp["version"], lp.get("base"))
            if adv:
                up = next((u for u in updates if u["name"] == name), None)
                vulnerable.append({"name": name, "version": lp["version"], "explicit": lp.get("explicit", False), "cve": tracker.cve_ids(adv),
                                   "risk": tracker.risk_of(adv), "advisories": adv, "fixed_by_update": bool(up and up["fixes"])})
        foreign = [p for p in local.values() if p["name"] not in sync]
        aur_updates = []
        if foreign:
            try:
                info = aur.rpc_info([p["name"] for p in foreign])
            except util.Fail:
                info = {}
            st = util.state()
            for p in foreign:
                m = info.get(p["name"])
                if m and vercmp(m["Version"], p["version"]) > 0:
                    aur_updates.append({"name": p["name"], "from": p["version"], "to": m["Version"], "votes": m.get("NumVotes"),
                                        "maintainer": m.get("Maintainer"), "out_of_date": m.get("OutOfDate"),
                                        "pinned_commit": st["aur"].get(p["name"], {}).get("commit"), "needs_review": True})
        res = {"ok": True, "checked": int(time.time()), "tracker_fetched": trk.fetched, "tracker_error": trk.error,
               "updates": updates, "aur_updates": aur_updates, "vulnerable": vulnerable,
               "summary": {"updates": len(updates), "security_updates": sum(1 for u in updates if u["security"]),
                           "blocked": sum(1 for u in updates if u["blocked"]), "aur_updates": len(aur_updates),
                           "vulnerable": len(vulnerable), "vulnerable_high": sum(1 for v in vulnerable if v["risk"] == "high")}}
        if util.is_root():
            util.write_json(util.CHECK_FILE, res)
        return res
    finally:
        shutil.rmtree(td, ignore_errors=True)


def upgrade(yes, allow):
    require_enabled()
    with util.Lock():
        entries, warnings, db = transact([], yes, allow, what="upgrade")
        st = util.state()
        db = DB()
        exports.refresh(db, st)
        util.save_state(st)
        clean_cache()
    res = {"ok": True, "upgraded": [entry_out(e) for e in entries], "warnings": [entry_out(e) for e in warnings]}
    try:
        c = check()
        res["aur_updates"] = c["aur_updates"]
        res["vulnerable"] = c["summary"]["vulnerable"]
    except util.Fail:
        pass
    return res


def build_one(r, names, asdeps, network):
    pkgbase = r["pkgbase"]
    uid = util.BUILDER_UID
    os.makedirs(util.BUILD, mode=0o700, exist_ok=True)
    os.chmod(util.BUILD, 0o700)
    os.makedirs(os.path.join(util.ROOT, "build"), mode=0o755, exist_ok=True)
    bdir = os.path.join(util.BUILD, "%s-%s" % (pkgbase, r["commit"][:12]))
    if os.path.exists(bdir):
        shutil.rmtree(bdir)
    os.makedirs(bdir)
    for sub in ("src", "home", "out", "work", "srcdest"):
        os.makedirs(os.path.join(bdir, sub))
    aur.write_tree(r["files"], os.path.join(bdir, "src"), uid)
    for dp, dn, fn in os.walk(bdir):
        os.chown(dp, uid, uid)
    env = {"PKGDEST": "/build/out", "SRCDEST": "/build/srcdest", "BUILDDIR": "/build/work", "MAKEFLAGS": "-j%d" % (os.cpu_count() or 2),
           "PACKAGER": "kwick-arch AUR build <%s@%s>" % (pkgbase, r["commit"][:12]), "GNUPGHOME": "/build/home/.gnupg", "LANG": "C.UTF-8"}
    binds = [(bdir, "/build", True)]
    keys = r["srcinfo"]["base"].get("validpgpkeys", [])
    if keys:
        util.say("Importing %d PGP key(s) listed in validpgpkeys ..." % len(keys))
        container.in_root(["gpg", "--batch", "--keyserver", "hkps://keyserver.ubuntu.com", "--recv-keys"] + keys, ro=True, binds=binds, env=env,
                          user=True, cwd="/build/src", check=False)
    util.say("Downloading and verifying sources for %s (commit %s) ..." % (pkgbase, r["commit"][:12]))
    container.in_root(["makepkg", "--nobuild", "--nodeps", "--noconfirm", "--noprogressbar"], ro=True, binds=binds, env=env, user=True, cwd="/build/src")
    util.say("Building %s %s ..." % (pkgbase, "with network access" if network else "without network access"))
    r2 = container.in_root(["makepkg", "--noextract", "--nodeps", "--noconfirm", "--holdver", "--noprogressbar", "--force"], ro=True, binds=binds,
                           env=env, user=True, cwd="/build/src", net=network, check=False)
    if r2.returncode != 0:
        raise util.Fail("build-failed", "makepkg failed for %s (exit %d)%s" % (pkgbase, r2.returncode,
                        "" if network else "; if the build needs the network, re-run with --build-network after reviewing why"))
    built = sorted(glob.glob(os.path.join(bdir, "out", "*.pkg.tar.*")))
    built = [b for b in built if not b.endswith(".sig")]
    pick = []
    for b in built:
        fn = os.path.basename(b)
        for n in names:
            if re.match(re.escape(n) + r"-[^-]+-[^-]+-[^-]+\.pkg\.tar\.", fn):
                pick.append(b)
    if not pick:
        raise util.Fail("build-failed", "makepkg produced no package named %s" % ", ".join(names))
    staged = []
    os.makedirs(os.path.join(util.ROOT, "var/cache/kwick-aur"), exist_ok=True)
    for b in pick:
        dst = os.path.join(util.ROOT, "var/cache/kwick-aur", os.path.basename(b))
        shutil.copyfile(b, dst)
        staged.append("/var/cache/kwick-aur/" + os.path.basename(b))
    container.pacman(["-U"] + (["--asdeps"] if asdeps else []) + staged)
    for s in staged:
        try:
            os.unlink(os.path.join(util.ROOT, s.lstrip("/")))
        except OSError:
            pass
    shutil.rmtree(bdir, ignore_errors=True)


def resolve_aur(targets, commit, db):
    reviews = {}
    order = []
    want = {}
    repo_deps = set()
    make_deps = set()
    pending = list(targets)
    metas = aur.rpc_info(pending)
    for t in targets:
        if t not in metas:
            raise util.Fail("not-found", "%s is not in the AUR" % t, util.EXIT_NOTFOUND, package=t)
    depth = 0
    while pending:
        depth += 1
        if depth > 50:
            raise util.Fail("dep-loop", "AUR dependency chain is too deep")
        name = pending.pop(0)
        m = metas.get(name)
        if not m:
            found = aur.rpc_search(name, by="provides")
            m = next((x for x in found if x["Name"] == name), found[0] if len(found) == 1 else None)
            if not m:
                raise util.Fail("missing-dependency", "dependency %s is neither in the Arch repositories nor in the AUR" % name, util.EXIT_NOTFOUND)
            metas[m["Name"]] = m
        b = m["PackageBase"]
        want.setdefault(b, [])
        if m["Name"] not in want[b]:
            want[b].append(m["Name"])
        if b in reviews:
            continue
        r = aur.review(m["Name"], commit if (commit and m["Name"] in targets) else None, meta=m)
        reviews[b] = r
        order.insert(0, b)
        info = r["srcinfo"]
        for dep in aur.si(info, "depends", m["Name"]) + aur.si(info, "makedepends") + aur.si(info, "checkdepends"):
            mk = dep in aur.si(info, "makedepends") + aur.si(info, "checkdepends")
            if db.installed_satisfies(dep):
                continue
            rp = db.repo_satisfies(dep)
            if rp:
                (make_deps if mk else repo_deps).add(rp["name"])
                continue
            dn = split_dep(dep)[0]
            if dn not in metas:
                metas.update(aur.rpc_info([dn]))
            pending.append(dn if dn in metas else dn)
    seen = []
    for b in order:
        if b not in seen:
            seen.append(b)
    return reviews, seen, want, sorted(repo_deps), sorted(make_deps - repo_deps)


def print_review(r):
    p = r["package"]
    util.say("")
    util.say("=== AUR review: %s %s (base %s, commit %s) ===" % (p["name"], r["version"], r["pkgbase"], r["commit"]))
    util.say("maintainer %s, votes %s, popularity %.3f, %s" % (p["maintainer"] or "NONE (orphaned)", p["votes"], p["popularity"], p["aur_url"]))
    util.say("risk: %s" % r["risk"].upper())
    for f in r["findings"]:
        where = (" [%s:%s]" % (f.get("file"), f.get("line"))) if f.get("line") else (" [%s]" % f["file"] if f.get("file") else "")
        util.say("  %-6s %s%s" % (f["severity"], f["message"], where))
    util.say("--- PKGBUILD ---")
    util.say(r["pkgbuild"].rstrip())
    for name in sorted(set(r["srcinfo"]["base"].get("install", []))):
        data = r["files"].get(name)
        if isinstance(data, bytes):
            util.say("--- %s (runs as root on install) ---" % name)
            util.say(data.decode("utf-8", "replace").rstrip())
    util.say("--- end of review ---")


def install_aur(targets, yes, allow, commit, network):
    require_enabled()
    if commit and len(targets) != 1:
        raise util.Fail("usage", "--commit pins one package", util.EXIT_USAGE)
    with util.Lock():
        refresh_db()
        db = DB()
        reviews, order, want, repo_deps, make_deps = resolve_aur(targets, commit, db)
        if not util.Out.json or sys.stdin.isatty():
            for b in order:
                print_review(reviews[b])
        summary = [{"pkgbase": b, "packages": want[b], "commit": reviews[b]["commit"], "risk": reviews[b]["risk"],
                    "findings": reviews[b]["findings"], "version": reviews[b]["version"]} for b in order]
        if not yes:
            if not sys.stdin.isatty():
                raise util.Fail("confirm", "AUR packages need an explicit confirmation after review (pass --yes, ideally with --commit from 'kwick-arch info --aur')",
                                util.EXIT_CONFIRM, review=summary, repo_dependencies=repo_deps, make_dependencies=make_deps)
            for b in order:
                r = reviews[b]
                q = "Build and install %s from AUR commit %s (risk %s)?" % (", ".join(want[b]), r["commit"][:12], r["risk"])
                if r["risk"] == "high":
                    try:
                        a = input("%s This review found HIGH risk issues. Type the package base name '%s' to continue: " % (q, b)).strip()
                    except EOFError:
                        a = ""
                    if a != b:
                        raise util.Fail("confirm", "not confirmed", util.EXIT_CONFIRM)
                elif not util.confirm(q, False):
                    raise util.Fail("confirm", "not confirmed", util.EXIT_CONFIRM)
        if not any(db.installed_satisfies(t) for t in ["base-devel"]):
            make_deps = sorted(set(make_deps) | {"base-devel"})
        if any(s["vcs"] and s["url"] and s["url"].startswith("git") for b in order for s in reviews[b]["sources"]) and not db.installed_satisfies("git"):
            make_deps = sorted(set(make_deps) | {"git"})
        need = sorted(set(repo_deps) | set(make_deps))
        before = set(DB().local())
        if need:
            util.say("Installing repository dependencies: %s" % " ".join(need))
            transact(need, True, allow, asdeps=True, refresh=False)
        installed = []
        try:
            for b in order:
                r = reviews[b]
                is_target = any(n in targets for n in want[b])
                build_one(r, want[b], not is_target, network or util.conf("AUR_NETWORK_BUILD") == "1")
                st = util.state()
                for n in want[b]:
                    st["aur"][n] = {"pkgbase": b, "commit": r["commit"], "digest": r["digest"], "version": r["version"], "risk": r["risk"],
                                    "findings": len([f for f in r["findings"] if f["severity"] != "info"]), "installed_at": int(time.time())}
                util.save_state(st)
                installed += want[b]
        finally:
            after = DB().local()
            orphans = [n for n in make_deps if n in after and n not in before and not after[n]["explicit"] and n not in TOOLCHAIN]
            if orphans:
                container.pacman(["-Rns"] + orphans, check=False)
        st = util.state()
        db = DB()
        add_requested(st, [t for t in targets if t in db.local()])
        exports.refresh(db, st, only=set(targets))
        util.save_state(st)
        clean_cache()
    return {"ok": True, "installed": installed, "aur": summary, "repo_dependencies": repo_deps,
            "exports": {n: exports.listing(st, n) for n in targets}}
