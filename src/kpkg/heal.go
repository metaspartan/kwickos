package main

// Self-healing compatibility.
//
// KwickOS ships BusyBox instead of GNU coreutils & friends. Debian
// maintainer scripts occasionally use a GNU-only option or an Essential
// tool/interpreter without declaring it. When a script fails, kpkg looks at
// its output, installs the real Debian package that provides the missing
// behaviour (coreutils, grep, perl-base, ...) and retries the script once.
// The base stays tiny; GNU tools appear only when real software needs them.

import (
	"bytes"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// toolPkg maps a command name to the Debian package providing the GNU version.
var toolPkg = map[string]string{
	"grep": "grep", "egrep": "grep", "fgrep": "grep", "sed": "sed", "tar": "tar", "gzip": "gzip", "gunzip": "gzip",
	"zcat": "gzip", "find": "findutils", "xargs": "findutils", "diff": "diffutils", "cmp": "diffutils",
	"awk": "mawk", "logger": "bsdutils", "mount": "mount", "umount": "mount", "su": "util-linux", "login": "login",
	"hostname": "hostname", "which": "debianutils", "run-parts": "debianutils", "tempfile": "debianutils",
	"ps": "procps", "pgrep": "procps", "pkill": "procps", "watch": "procps", "kill": "procps", "pidof": "procps", "sysctl": "procps", "free": "procps", "top": "procps",
	"getopt": "util-linux", "flock": "util-linux", "mkswap": "util-linux", "lsblk": "util-linux", "blkid": "util-linux",
	"start-stop-daemon": "dpkg", "getent": "libc-bin", "ldconfig": "libc-bin", "iconv": "libc-bin", "locale": "libc-bin",
	"useradd": "passwd", "usermod": "passwd", "groupadd": "passwd", "chpasswd": "passwd", "chage": "passwd",
	"adduser": "adduser", "addgroup": "adduser", "deluser": "adduser", "ucf": "ucf", "ucfr": "ucf",
	"install-info": "install-info", "perl": "perl-base", "bash": "bash", "python3": "python3", "gawk": "gawk",
	"ip": "iproute2", "ss": "iproute2", "lsb_release": "lsb-release", "openssl": "openssl", "dpkg-reconfigure": "debconf",
}

// everything else that is a busybox applet comes from coreutils.
const defaultGNU = "coreutils"

var (
	reUsage   = regexp.MustCompile(`(?m)^(?:Usage|BusyBox v[^\n]*\n\nUsage): ([a-z0-9_.-]+)`)
	reBadOpt  = regexp.MustCompile(`(?m)^([a-z0-9_.-]+): (?:unrecognized|invalid|unknown)(?: option)?[: ]`)
	reNoCmd   = regexp.MustCompile(`(?m)(?:^|: )([A-Za-z0-9_./+-]+): (?:not found|command not found)$`)
	reBadDate = regexp.MustCompile(`(?m)^(date|touch|stat|ls|cp|mv|install|chown|chmod|ln|mktemp|readlink|realpath|sort|head|tail|cut|tr|wc|basename|dirname|env|id|seq|timeout|nproc|numfmt|od|md5sum|sha256sum|base64|du|df|mkdir|rm|rmdir|cat|echo|printf|test|touch|uname): `)
)

func isBusyboxApplet(cmd string) bool {
	data, err := os.ReadFile(filepath.Join(cfg.Root, "usr/share/kwick/busybox.links"))
	if err != nil {
		return false
	}
	for _, l := range strings.Split(string(data), "\n") {
		if filepath.Base(l) == cmd {
			p, err := resolveInRoot(cfg.Root, l, false)
			if err != nil {
				return false
			}
			t, err := os.Readlink(p)
			return err == nil && strings.HasSuffix(t, "busybox")
		}
	}
	return false
}

func interpreterOf(cmd string) string {
	var path string
	if strings.Contains(cmd, "/") {
		path = filepath.Join(cfg.Root, cmd)
	} else {
		for _, d := range []string{"usr/local/sbin", "usr/local/bin", "usr/sbin", "usr/bin", "sbin", "bin"} {
			p := filepath.Join(cfg.Root, d, cmd)
			if _, err := os.Stat(p); err == nil {
				path = p
				break
			}
		}
	}
	if path == "" {
		return ""
	}
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	b := make([]byte, 128)
	n, _ := f.Read(b)
	b = b[:n]
	if !bytes.HasPrefix(b, []byte("#!")) {
		return ""
	}
	line := strings.Fields(string(b[2:bytes.IndexByte(append(b, '\n'), '\n')]))
	if len(line) == 0 {
		return ""
	}
	interp := line[0]
	if filepath.Base(interp) == "env" && len(line) > 1 {
		interp = line[1]
	}
	return filepath.Base(interp)
}

// diagnose returns the Debian package that would fix a failed script.
func (db *DB) diagnose(output string) (pkg, why string) {
	want := func(tool string) string {
		if p, ok := toolPkg[tool]; ok {
			return p
		}
		return defaultGNU
	}
	for _, re := range []*regexp.Regexp{reBadOpt, reUsage} {
		if m := re.FindStringSubmatch(output); m != nil && isBusyboxApplet(m[1]) {
			return want(m[1]), "busybox " + m[1] + " lacks a GNU option"
		}
	}
	if m := reNoCmd.FindStringSubmatch(output); m != nil {
		cmd := m[1]
		if interp := interpreterOf(cmd); interp != "" {
			if p, ok := toolPkg[interp]; ok {
				return p, cmd + " needs interpreter " + interp
			}
		}
		if p, ok := toolPkg[filepath.Base(cmd)]; ok {
			return p, "missing command " + cmd
		}
	}
	if m := reBadDate.FindStringSubmatch(output); m != nil && isBusyboxApplet(m[1]) &&
		(strings.Contains(output, "invalid") || strings.Contains(output, "can't")) {
		return want(m[1]), "busybox " + m[1] + " behaviour differs from GNU"
	}
	return "", ""
}

// heal installs pkgName (and deps) inside the running transaction.
func (tx *Tx) heal(pkgName, why string) bool {
	if tx.healed == nil {
		tx.healed = map[string]bool{}
	}
	if tx.healed[pkgName] {
		return false
	}
	tx.healed[pkgName] = true
	db := tx.db
	db.LoadAvailable()
	c := db.Candidate(pkgName)
	if c == nil {
		return false
	}
	if in := db.lookupInstalled(pkgName); in != nil && in.Field("X-Kwick-Base") != "yes" && in.State() == "installed" {
		return false
	}
	warn("compat: %s; installing %s and retrying", why, pkgName)
	pl := db.NewPlan(ResolveOpts{Upgrade: false})
	pl.Add(c, false)
	if err := pl.Resolve(); err != nil {
		warn("compat: cannot resolve %s: %v", pkgName, err)
		return false
	}
	var list []*Pkg
	for _, n := range sortedKeys(pl.Install) {
		list = append(list, pl.Install[n])
	}
	files, err := Download(list)
	if err != nil {
		warn("compat: %v", err)
		return false
	}
	saved := tx.plan
	tx.plan = pl
	defer func() { tx.plan = saved }()
	for _, g := range pl.Order() {
		for _, p := range g {
			if err := tx.unpack(p, files[p]); err != nil {
				warn("compat: %v", err)
				return false
			}
		}
		for _, p := range g {
			if err := tx.configure(p); err != nil {
				warn("compat: %v", err)
				return false
			}
		}
	}
	for n := range pl.NewAuto {
		db.Auto[n] = true
	}
	if !cfg.KeepDebs {
		for _, f := range files {
			os.Remove(f)
		}
	}
	return true
}
