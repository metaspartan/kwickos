package main

// "Essential on demand".
//
// Debian maintainer scripts may use anything from the Essential set
// without declaring it. KwickOS satisfies most of that set with BusyBox,
// but not perl (debconf, many postinsts) or a full bash, and glibc users
// expect libc-bin (ldconfig, getent). Instead of shipping them in the base
// image, kpkg pulls them in the moment a transaction actually needs them.

import (
	"bytes"
	"strings"
)

// implicitDeps: installing the key also needs the values.
var implicitDeps = map[string][]string{
	"debconf": {"perl-base"},
	"libc6":   {"libc-bin"},
}

func (pl *Plan) needs(name string) bool {
	if _, ok := pl.Install[name]; ok {
		return false
	}
	in := pl.db.lookupInstalled(name)
	return in == nil || in.Field("X-Kwick-Base") == "yes"
}

// addImplicit adds static implicit deps; returns true if the plan grew.
func (pl *Plan) addImplicit() bool {
	grew := false
	for _, n := range sortedKeys(pl.Install) {
		for _, dep := range implicitDeps[n] {
			if pl.needs(dep) {
				if c := pl.db.Candidate(dep); c != nil {
					pl.Add(c, false)
					grew = true
				}
			}
			pl.addEdge(n, dep)
		}
	}
	return grew
}

// scriptNeeds inspects maintainer-script interpreters of downloaded debs.
func (pl *Plan) scriptNeeds(files map[*Pkg]string) []string {
	want := map[string]bool{}
	for p, f := range files {
		if pl.Install[p.Name] != p {
			continue
		}
		dc, err := ReadDebControl(f)
		if err != nil {
			continue
		}
		for _, s := range []string{"preinst", "postinst", "prerm", "postrm", "config"} {
			b := dc.Files[s]
			if len(b) < 3 || !bytes.HasPrefix(b, []byte("#!")) {
				continue
			}
			line := string(b[2:bytes.IndexByte(append(b, '\n'), '\n')])
			switch {
			case strings.Contains(line, "perl"):
				want["perl-base"] = true
				pl.addEdge(p.Name, "perl-base")
			case strings.Contains(line, "bash"):
				want["bash"] = true
				pl.addEdge(p.Name, "bash")
			}
			if bytes.Contains(b, []byte("/usr/share/debconf/confmodule")) && p.Name != "debconf" {
				if _, planned := pl.Install["debconf"]; planned {
					pl.addEdge(p.Name, "debconf")
				}
			}
		}
	}
	var out []string
	for n := range want {
		if pl.needs(n) && pl.db.Candidate(n) != nil {
			out = append(out, n)
		}
	}
	return out
}

func (pl *Plan) addEdge(from, to string) {
	if pl.extra == nil {
		pl.extra = map[string][]string{}
	}
	for _, x := range pl.extra[from] {
		if x == to {
			return
		}
	}
	pl.extra[from] = append(pl.extra[from], to)
}

// configRank orders configuration inside a dependency cycle: Essential
// packages (perl-base, libc-bin) first, then debconf, then the rest.
func configRank(p *Pkg) int {
	switch {
	case p.Essential() || p.Name == "libc6":
		return 0
	case p.Name == "debconf":
		return 1
	}
	return 2
}
