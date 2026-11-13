package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

func archFile() string { return filepath.Join(cfg.Admin, "arch") }

func loadForeignArches() []string {
	data, err := os.ReadFile(archFile())
	if err != nil {
		return nil
	}
	var out []string
	for _, l := range strings.Split(string(data), "\n") {
		a := strings.TrimSpace(l)
		if a != "" && a != cfg.Arch && a != "all" && a != "any" && !contains(out, a) {
			out = append(out, a)
		}
	}
	return out
}

func saveForeignArches(list []string) error {
	os.MkdirAll(cfg.Admin, 0755)
	var b strings.Builder
	for _, a := range list {
		b.WriteString(a + "\n")
	}
	if b.Len() == 0 {
		if err := os.Remove(archFile()); err != nil && !os.IsNotExist(err) {
			return err
		}
		return nil
	}
	return os.WriteFile(archFile(), []byte(b.String()), 0644)
}

func allArches() []string {
	return append([]string{cfg.Arch}, cfg.Foreign...)
}

func validArchName(a string) bool {
	if a == "" {
		return false
	}
	for _, c := range a {
		if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-') {
			return false
		}
	}
	return true
}

func knownArch(a string) bool {
	return a == "all" || a == cfg.Arch || contains(cfg.Foreign, a)
}

func addArchitecture(a string) error {
	if !validArchName(a) {
		return fmt.Errorf("invalid architecture name '%s'", a)
	}
	if a == "all" || a == "any" {
		return fmt.Errorf("cannot add the '%s' pseudo-architecture", a)
	}
	if a == cfg.Arch || contains(cfg.Foreign, a) {
		return nil
	}
	list := append(append([]string(nil), cfg.Foreign...), a)
	if err := saveForeignArches(list); err != nil {
		return err
	}
	cfg.Foreign = list
	return nil
}

func removeArchitecture(a string) error {
	if !validArchName(a) {
		return fmt.Errorf("invalid architecture name '%s'", a)
	}
	if !contains(cfg.Foreign, a) {
		return nil
	}
	db, err := OpenDB()
	if err != nil {
		return err
	}
	for _, in := range db.Installed {
		if in.Arch == a && in.State() != "not-installed" {
			return fmt.Errorf("cannot remove architecture '%s' currently in use by the database", a)
		}
	}
	var list []string
	for _, x := range cfg.Foreign {
		if x != a {
			list = append(list, x)
		}
	}
	if err := saveForeignArches(list); err != nil {
		return err
	}
	cfg.Foreign = list
	return nil
}

func keyOf(name, arch string) string {
	if arch == "" || arch == "all" || arch == cfg.Arch {
		return name
	}
	return name + ":" + arch
}

func splitKey(k string) (name, arch string) {
	if i := strings.IndexByte(k, ':'); i >= 0 {
		return k[:i], k[i+1:]
	}
	return k, ""
}

func infoNameFor(name, arch, multiArch string) string {
	switch {
	case arch == "" || arch == "all":
		return name
	case multiArch == "same" || arch != cfg.Arch:
		return name + ":" + arch
	}
	return name
}

func (p *Pkg) Key() string { return keyOf(p.Name, p.Arch) }

func (p *Pkg) MultiArch() string { return p.Field("Multi-Arch") }

func (p *Pkg) selfArch() string {
	if p.Arch == "" || p.Arch == "all" {
		return cfg.Arch
	}
	return p.Arch
}

func archFits(q, from string, t *Pkg) bool {
	ta, ma := t.Arch, t.MultiArch()
	if ta == "all" || ta == "" {
		return true
	}
	switch q {
	case "":
		return ta == from || ma == "foreign"
	case "any":
		return ta == from || ma == "allowed" || ma == "foreign"
	case "native":
		return ta == cfg.Arch
	}
	return ta == q
}

func depArchOK(d Dep) bool {
	switch d.Arch {
	case "", "any", "native", "all":
		return true
	}
	return knownArch(d.Arch)
}

func nameKeys(name string) []string {
	ks := make([]string, 0, 1+len(cfg.Foreign))
	for _, a := range allArches() {
		ks = append(ks, keyOf(name, a))
	}
	return ks
}

func archRank(c *Pkg, from string) int {
	if c.Arch == "all" {
		return 0
	}
	if c.MultiArch() == "foreign" {
		switch c.Arch {
		case cfg.Arch:
			return 0
		case from:
			return 1
		}
		return 2
	}
	switch c.Arch {
	case from:
		return 0
	case cfg.Arch:
		return 1
	}
	return 2
}

func (p *Pkg) sameInstance(q *Pkg) bool { return p.Name == q.Name && p.Arch == q.Arch }

func (db *DB) installedInstances(name string) []*Installed {
	var out []*Installed
	for _, k := range sortedKeys(db.Installed) {
		if in := db.Installed[k]; in.Name == name && in.State() != "not-installed" {
			out = append(out, in)
		}
	}
	return out
}

func (db *DB) installedMatching(d Dep, from string) []*Installed {
	var out []*Installed
	for _, k := range nameKeys(d.Name) {
		if in := db.lookupInstalled(k); in != nil && archFits(d.Arch, from, in.Pkg) && VersionSatisfies(in.Version, d.Op, d.Ver) {
			out = append(out, in)
		}
	}
	return out
}

func scriptIdentity(infoName string) (name, arch string, refcount int) {
	name, arch = splitKey(infoName)
	if arch == "" || arch == "all" {
		arch = cfg.Arch
	}
	refcount = 1
	if curDB != nil {
		refcount = len(curDB.installedInstances(name))
		if curDB.lookupInstalled(infoName) == nil {
			refcount++
		}
		if refcount < 1 {
			refcount = 1
		}
	}
	return
}

func (db *DB) installedByKey(key string) *Installed {
	if in := db.lookupInstalled(key); in != nil && in.Key() == key {
		return in
	}
	return nil
}

func markKey(db *DB, n string) string {
	if in := db.lookupInstalled(n); in != nil {
		return in.Key()
	}
	return n
}

func matchInstalledPattern(pat string, in *Installed) bool {
	for _, n := range []string{in.Name, in.InfoName(), in.Name + ":" + in.Arch} {
		if ok, _ := filepath.Match(pat, n); ok {
			return true
		}
	}
	return false
}

func (pl *Plan) syncSameVersions() (bool, error) {
	changed := false
	for _, k := range sortedKeys(pl.Install) {
		p := pl.Install[k]
		if p.MultiArch() != "same" {
			continue
		}
		var others []*Pkg
		for _, ok := range nameKeys(p.Name) {
			if ok == k {
				continue
			}
			if q, found := pl.effective(ok); found && q.Name == p.Name && q.MultiArch() == "same" {
				others = append(others, q)
			}
		}
		sort.Slice(others, func(i, j int) bool { return others[i].Arch < others[j].Arch })
		for _, q := range others {
			if q.Version == p.Version {
				continue
			}
			if _, planned := pl.Install[q.Key()]; !planned {
				var match *Pkg
				for _, c := range pl.db.Avail[q.Key()] {
					if c.Version == p.Version {
						match = c
						break
					}
				}
				if match != nil {
					pl.Add(match, false)
					changed = true
					continue
				}
			}
			return false, fmt.Errorf("%s %s and %s %s are both Multi-Arch: same but their versions differ; cannot co-install",
				p.Key(), p.Version, q.Key(), q.Version)
		}
	}
	return changed, nil
}
