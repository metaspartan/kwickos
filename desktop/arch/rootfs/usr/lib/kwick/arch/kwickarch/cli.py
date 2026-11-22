import os
import signal
import sys
import time

from . import aur, container, exports, ops, tracker, util
from .pacdb import DB

USAGE = """usage: kwick-arch <command> [options]

  status [--json]                         state of the Arch environment
  enable | disable [--purge]              create (from the signed Arch bootstrap) or switch off the environment
  search QUERY [--aur] [--json]           search core/extra/multilib, or the AUR
  info PKG [--aur] [--commit SHA] [--json]
                                          details, open CVEs; for the AUR the PKGBUILD and a risk report
  install PKG... [--aur] [--yes] [--allow-vulnerable] [--commit SHA] [--build-network] [--json]
  remove PKG... [--json]
  upgrade [--check] [--yes] [--allow-vulnerable] [--json]
  list [--all] [--json]                   installed packages (explicit ones unless --all)
  run [--] COMMAND [ARGS...]              run a program from the Arch environment as you
  shell                                   interactive shell in the Arch environment

Repository packages with open issues in the Arch Security Tracker are refused
(override: --allow-vulnerable). AUR packages are reviewed, need confirmation,
are built as an unprivileged user without network access and pinned to the
reviewed commit.
"""

FLAGS = {"--json", "--aur", "--yes", "-y", "--allow-vulnerable", "--check", "--all", "--purge", "--build-network", "--quiet", "-q"}
VALUED = {"--commit"}


def parse(argv):
    flags = set()
    vals = {}
    pos = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--":
            pos += argv[i + 1:]
            break
        if a in FLAGS:
            flags.add("--yes" if a == "-y" else "--quiet" if a == "-q" else a)
        elif a in VALUED:
            if i + 1 >= len(argv):
                raise util.Fail("usage", "%s needs a value" % a, util.EXIT_USAGE)
            vals[a] = argv[i + 1]
            i += 1
        elif a.startswith("--") and "=" in a and a.split("=", 1)[0] in VALUED:
            k, v = a.split("=", 1)
            vals[k] = v
        elif a.startswith("-") and len(a) > 1:
            raise util.Fail("usage", "unknown option " + a, util.EXIT_USAGE)
        else:
            pos.append(a)
        i += 1
    return flags, vals, pos


def tracker_or_none():
    try:
        return tracker.Tracker().load(), None
    except util.Fail as e:
        return None, e.message


def cmd_status():
    ok, why = util.supported()
    st = util.state()
    present = container.root_present()
    db = DB() if present else None
    local = db.local() if db else {}
    chk = util.read_json(util.CHECK_FILE) or {}
    tf = 0
    for p in (os.path.join(util.CACHE, "tracker.json"),):
        try:
            tf = int(os.stat(p).st_mtime)
        except OSError:
            pass
    foreign = [p for p in db.foreign()] if db and db.sync() else []
    res = {
        "ok": True,
        "version": util.version(),
        "arch": util.machine(),
        "supported": ok,
        "reason": why,
        "enabled": bool(st.get("enabled")) and present,
        "present": present,
        "root": util.ROOT,
        "bootstrap": st.get("bootstrap"),
        "userns": container.userns_ok(),
        "bwrap": bool(__import__("shutil").which("bwrap")),
        "packages": len(local),
        "explicit": sum(1 for p in local.values() if p.get("explicit")),
        "aur": sorted(p["name"] for p in foreign),
        "exports": {k: exports.listing(st, k) for k in sorted(st.get("exports", {}))},
        "disk_bytes": util.dir_size(util.ROOT) if present else 0,
        "tracker_fetched": tf,
        "last_check": {"checked": chk.get("checked"), "summary": chk.get("summary")} if chk else None,
    }
    if util.Out.json:
        return res
    print("Arch environment  %s" % ("enabled" if res["enabled"] else ("present, disabled" if present else "not set up")))
    if not ok:
        print("supported         no: " + why)
    print("root              %s" % util.ROOT)
    if res["bootstrap"]:
        print("bootstrap         %s (signed by %s)" % (res["bootstrap"].get("file"), res["bootstrap"].get("signer")))
    print("packages          %d (%d explicit, %d from the AUR)" % (res["packages"], res["explicit"], len(res["aur"])))
    print("exported apps     %d" % sum(len(v["desktop"]) for v in res["exports"].values()))
    if present:
        print("disk              %.1f MiB" % (res["disk_bytes"] / 1048576))
    if res["last_check"] and res["last_check"]["summary"]:
        s = res["last_check"]["summary"]
        print("last check        %s: %d update(s), %d vulnerable package(s)" % (time.strftime("%Y-%m-%d %H:%M", time.localtime(res["last_check"]["checked"])), s["updates"], s["vulnerable"]))
    return None


def repo_result(p, trk, local):
    adv = trk.issues(p["name"], p["version"], p.get("base")) if trk else []
    lp = local.get(p["name"])
    return {"name": p["name"], "version": p["version"], "repo": p["repo"], "description": p["description"], "url": p["url"],
            "installed": lp["version"] if lp else None, "size": p["csize"], "installed_size": p["isize"],
            "cve": tracker.cve_ids(adv), "advisories": adv, "risk": tracker.risk_of(adv) if trk else "unknown"}


def cmd_search(q, use_aur):
    if not q:
        raise util.Fail("usage", "search needs a query", util.EXIT_USAGE)
    query = " ".join(q)
    trk, terr = tracker_or_none()
    if use_aur:
        rs = aur.rpc_search(query)
        rs.sort(key=lambda m: (m["Name"] != query, -(m.get("Popularity") or 0), m["Name"]))
        local = DB().local() if container.root_present() else {}
        out = []
        for m in rs[:250]:
            mf = aur.meta_findings(m)
            adv = trk.issues(m["Name"], m["Version"]) if trk else []
            out.append({"name": m["Name"], "version": m["Version"], "repo": "aur", "description": m.get("Description") or "",
                        "url": m.get("URL"), "votes": m.get("NumVotes") or 0, "popularity": m.get("Popularity") or 0,
                        "maintainer": m.get("Maintainer"), "out_of_date": m.get("OutOfDate"), "first_submitted": m.get("FirstSubmitted"),
                        "last_modified": m.get("LastModified"), "installed": local.get(m["Name"], {}).get("version"),
                        "cve": tracker.cve_ids(adv), "risk": aur.risk(mf + [{"severity": "high" if tracker.risk_of(adv) == "high" and adv else "info"}]),
                        "risk_basis": "metadata", "findings": mf})
    else:
        ops.require_enabled()
        db = DB()
        local = db.local()
        terms = [t.lower() for t in q]
        hits = []
        for p in db.sync():
            hay = (p["name"] + " " + p["description"]).lower()
            if all(t in hay for t in terms):
                n = p["name"].lower()
                score = 0 if n == query.lower() else 1 if n.startswith(terms[0]) else 2 if terms[0] in n else 3
                hits.append((score, p["name"], p))
        hits.sort(key=lambda x: (x[0], x[1]))
        out = [repo_result(p, trk, local) for _, _, p in hits[:250]]
    if util.Out.json:
        return {"ok": True, "query": query, "source": "aur" if use_aur else "repos", "tracker_error": terr, "results": out}
    for r in out:
        extra = (" votes %d pop %.2f" % (r["votes"], r["popularity"])) if use_aur else ""
        flag = (" [%d CVE]" % len(r["cve"])) if r["cve"] else ""
        inst = " [installed]" if r.get("installed") else ""
        print("%s/%s %s%s%s%s  risk %s" % (r["repo"], r["name"], r["version"], inst, flag, extra, r["risk"]))
        print("    " + (r["description"] or ""))
    if terr:
        util.warn("CVE data unavailable: " + terr)
    return None


def cmd_info(names, use_aur, commit):
    if len(names) != 1:
        raise util.Fail("usage", "info takes one package", util.EXIT_USAGE)
    name = names[0]
    trk, terr = tracker_or_none()
    st = util.state()
    local = DB().local() if container.root_present() else {}
    if use_aur:
        r = aur.review(name, commit)
        out = aur.review_out(r)
        adv = trk.issues(name, r["version"]) if trk else []
        out.update({"ok": True, "name": name, "version": r["version"], "repo": "aur", "cve": tracker.cve_ids(adv), "advisories": adv,
                    "installed": local.get(name, {}).get("version"), "pinned": st["aur"].get(name), "tracker_error": terr})
        if util.Out.json:
            return out
        ops.print_review(r)
        if out["pinned"]:
            print("installed from commit %s" % out["pinned"]["commit"])
        return None
    ops.require_enabled()
    db = DB()
    p = db.sync_by_name().get(name) or db.repo_satisfies(name)
    if not p:
        lp = local.get(name)
        if lp:
            p = dict(lp, repo="aur" if name in st["aur"] else "local")
        else:
            raise util.Fail("not-found", "%s is not in the Arch repositories (try --aur)" % name, util.EXIT_NOTFOUND)
    res = repo_result(p, trk, local)
    res.update({"ok": True, "base": p.get("base"), "licenses": p.get("licenses"), "depends": p.get("depends"), "optdepends": p.get("optdepends"),
                "provides": p.get("provides"), "conflicts": p.get("conflicts"), "groups": p.get("groups"), "packager": p.get("packager"),
                "builddate": p.get("builddate"), "tracker_error": terr, "exports": exports.listing(st, name) if name in local else None})
    if util.Out.json:
        return res
    for k in ("name", "version", "repo", "description", "url", "installed", "packager"):
        print("%-12s %s" % (k, res.get(k) or "-"))
    print("%-12s %s" % ("depends", " ".join(res["depends"] or []) or "-"))
    print("%-12s %s" % ("risk", res["risk"]))
    for a in res["advisories"]:
        print("  %s %s %s %s fixed:%s %s" % (a["avg"], a["severity"], a["status"], a["type"], a["fixed"] or "no", " ".join(a["cves"])))
    return None


def cmd_list(all_pkgs):
    ops.require_enabled()
    db = DB()
    st = util.state()
    trk, terr = tracker_or_none()
    sync = db.sync_by_name()
    out = []
    for n, p in sorted(db.local().items()):
        if not all_pkgs and not p.get("explicit"):
            continue
        adv = trk.issues(n, p["version"], p.get("base")) if trk else []
        repo = sync[n]["repo"] if n in sync else ("aur" if n in st["aur"] else "local")
        out.append({"name": n, "version": p["version"], "repo": repo, "explicit": p.get("explicit"), "description": p["description"],
                    "installed_size": p["isize"], "installdate": p.get("installdate"), "cve": tracker.cve_ids(adv), "advisories": adv,
                    "risk": tracker.risk_of(adv) if trk else "unknown", "exports": exports.listing(st, n), "aur": st["aur"].get(n)})
    if util.Out.json:
        return {"ok": True, "packages": out, "tracker_error": terr}
    for r in out:
        flag = (" [%d CVE]" % len(r["cve"])) if r["cve"] else ""
        print("%-32s %-24s %s%s" % (r["name"], r["version"], r["repo"], flag))
    return None


def cmd_check():
    res = None
    if not util.is_root():
        cached = util.read_json(util.CHECK_FILE)
        if cached and time.time() - cached.get("checked", 0) < 3600:
            res = dict(cached, cached=True)
    if res is None:
        res = ops.check()
    if util.Out.json:
        return res
    s = res["summary"]
    print("%d update(s) (%d fix security issues, %d blocked), %d AUR update(s) needing review, %d installed package(s) with open CVEs" % (
        s["updates"], s["security_updates"], s["blocked"], s["aur_updates"], s["vulnerable"]))
    for u in res["updates"]:
        print("  %-30s %s -> %s%s%s" % (u["name"], u["from"], u["to"], "  fixes " + " ".join(u["fixes"][:3]) if u["fixes"] else "", "  BLOCKED" if u["blocked"] else ""))
    for u in res["aur_updates"]:
        print("  aur/%-26s %s -> %s  (review with: kwick-arch info --aur %s)" % (u["name"], u["from"], u["to"], u["name"]))
    for v in res["vulnerable"]:
        print("  vulnerable %-22s %s  %s%s" % (v["name"], v["version"], " ".join(v["cve"][:4]), " (update available)" if v["fixed_by_update"] else ""))
    return None


def cmd_run(cmd):
    ops.require_enabled()
    if not cmd:
        cmd = ["/bin/bash", "-l"]
    argv = container.user_argv(cmd)
    os.execvp("bwrap", argv)


def human_done(res):
    if res.get("installed"):
        print("installed: " + " ".join(res["installed"]))
        for n, e in (res.get("exports") or {}).items():
            if e and (e["desktop"] or e["bin"]):
                print("  %s: %d menu entr%s, commands: %s" % (n, len(e["desktop"]), "y" if len(e["desktop"]) == 1 else "ies", " ".join(e["bin"]) or "-"))
    if res.get("removed"):
        print("removed: " + " ".join(res["removed"]))
    if "upgraded" in res:
        print("%d package(s) upgraded" % len(res["upgraded"]))
    for w in res.get("warnings") or []:
        print("warning: %s %s has known CVEs: %s" % (w["name"], w["version"], " ".join(w["cve"][:6])))


def dispatch(argv):
    if not argv or argv[0] in ("-h", "--help", "help"):
        sys.stdout.write(USAGE)
        return None
    cmd = argv[0]
    if cmd in ("run", "shell", "enter"):
        rest = argv[1:]
        if rest and rest[0] == "--":
            rest = rest[1:]
        return cmd_run(rest if cmd == "run" else ["/bin/bash", "-l"])
    flags, vals, pos = parse(argv[1:])
    util.Out.json = "--json" in flags
    util.Out.quiet = "--quiet" in flags
    yes = "--yes" in flags
    allow = "--allow-vulnerable" in flags
    if cmd == "status":
        return cmd_status()
    if cmd == "enable":
        util.elevate(argv)
        res = ops.enable(yes)
        return res if util.Out.json else print("The Arch environment is ready. Try: kwick-arch search QUERY")
    if cmd == "disable":
        util.elevate(argv)
        res = ops.disable("--purge" in flags)
        return res if util.Out.json else print("The Arch environment is disabled%s." % (" and removed" if res["purged"] else " (its files stay; --purge removes them)"))
    if cmd == "search":
        return cmd_search(pos, "--aur" in flags)
    if cmd == "info":
        return cmd_info(pos, "--aur" in flags, vals.get("--commit"))
    if cmd == "list":
        return cmd_list("--all" in flags)
    if cmd in ("install", "remove"):
        if not pos:
            raise util.Fail("usage", "%s needs at least one package" % cmd, util.EXIT_USAGE)
        util.elevate(argv)
        if cmd == "remove":
            res = ops.remove(pos, yes)
        elif "--aur" in flags:
            res = ops.install_aur(pos, yes, allow, vals.get("--commit"), "--build-network" in flags)
        else:
            res = ops.install_repo(pos, yes, allow)
        if util.Out.json:
            return res
        human_done(res)
        return None
    if cmd in ("upgrade", "update"):
        if "--check" in flags:
            return cmd_check()
        util.elevate(argv)
        res = ops.upgrade(yes, allow)
        if util.Out.json:
            return res
        human_done(res)
        return None
    if cmd == "audit":
        return cmd_check()
    if cmd == "_tsv":
        chk = util.read_json(util.CHECK_FILE) or {}
        if container.enabled():
            for u in chk.get("updates", []):
                desc = (u.get("description") or "-").replace("\t", " ").replace("\n", " ")
                print("arch\t%s\t%s\t%s\t%d\t%s\t%d" % (u["name"], u["from"], u["to"], u.get("size") or 0, desc, 1 if u.get("security") else 0))
        return None
    if cmd == "_summary":
        chk = util.read_json(util.CHECK_FILE) or {}
        on = bool(container.enabled())
        return {"enabled": on, "checked": chk.get("checked") if on else None, "summary": chk.get("summary") if on else None,
                "vulnerable": [{k: v.get(k) for k in ("name", "version", "cve", "risk", "fixed_by_update")} for v in chk.get("vulnerable", [])] if on else [],
                "aur_updates": chk.get("aur_updates", []) if on else []}
    raise util.Fail("usage", "unknown command '%s' (see kwick-arch --help)" % cmd, util.EXIT_USAGE)


def main(argv):
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    util.Out.json = "--json" in argv
    try:
        res = dispatch(argv)
        if res is not None:
            util.emit(res)
        return 0
    except util.Fail as e:
        if util.Out.json:
            obj = {"ok": False, "error": e.code, "message": e.message}
            obj.update(e.extra)
            util.emit(obj)
        else:
            util.warn(e.message)
        return e.status
    except KeyboardInterrupt:
        if util.Out.json:
            util.emit({"ok": False, "error": "interrupted", "message": "interrupted"})
        return 130
    except Exception as e:
        if util.Out.json:
            util.emit({"ok": False, "error": "internal", "message": "%s: %s" % (type(e).__name__, e)})
            return 1
        raise
