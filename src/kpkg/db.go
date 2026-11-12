package main

import (
	"bufio"
	"compress/gzip"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// Pkg is a package version (available from a repo, a local .deb, or installed).
type Pkg struct {
	P        *Paragraph
	Name     string
	Version  string
	Arch     string
	Src      *Source
	LocalDeb string
	deps     map[string][][]Dep
	provides []Provided
}

func newPkg(p *Paragraph) *Pkg {
	return &Pkg{P: p, Name: p.Get("Package"), Version: p.Get("Version"), Arch: p.Get("Architecture")}
}

func (p *Pkg) Field(k string) string { return p.P.Get(k) }

func (p *Pkg) Deps(field string) [][]Dep {
	if p.deps == nil {
		p.deps = map[string][][]Dep{}
	}
	d, ok := p.deps[field]
	if !ok {
		d = ParseDeps(p.P.Get(field), cfg.Arch)
		p.deps[field] = d
	}
	return d
}

func (p *Pkg) Provides() []Provided {
	if p.provides == nil {
		p.provides = ParseProvides(p.P.Get("Provides"))
		if p.provides == nil {
			p.provides = []Provided{}
		}
	}
	return p.provides
}

func (p *Pkg) Size() int64          { n, _ := strconv.ParseInt(p.Field("Size"), 10, 64); return n }
func (p *Pkg) InstalledSize() int64 { n, _ := strconv.ParseInt(p.Field("Installed-Size"), 10, 64); return n * 1024 }
func (p *Pkg) Essential() bool      { return p.Field("Essential") == "yes" || p.Field("Protected") == "yes" }
func (p *Pkg) MultiArchSame() bool  { return p.Field("Multi-Arch") == "same" }

// InfoName is the dpkg database name (pkg or pkg:arch for M-A: same).
func (p *Pkg) InfoName() string {
	if p.MultiArchSame() {
		return p.Name + ":" + p.Arch
	}
	return p.Name
}

func (p *Pkg) archOK() bool { return p.Arch == cfg.Arch || p.Arch == "all" }

// Installed is a package entry in /var/lib/dpkg/status.
type Installed struct {
	*Pkg
	Status string // e.g. "install ok installed"
}

func (i *Installed) State() string {
	f := strings.Fields(i.Status)
	if len(f) == 3 {
		return f[2]
	}
	return ""
}

type provider struct {
	pkg *Pkg
	ver string
}

type DB struct {
	Avail     map[string][]*Pkg // name -> versions (sorted newest first)
	Installed map[string]*Installed
	Order     []string // installed package order in status file
	provAvail map[string][]provider
	Auto      map[string]bool
}

func OpenDB() (*DB, error) {
	db := &DB{Avail: map[string][]*Pkg{}, Installed: map[string]*Installed{}, Auto: map[string]bool{}}
	if err := db.loadStatus(); err != nil {
		return nil, err
	}
	db.loadAuto()
	return db, nil
}

// LoadAvailable reads all compact indexes. Lazily called only by commands
// that need repository data, so `dpkg -l` etc. stay instant.
func (db *DB) LoadAvailable() error {
	if db.provAvail != nil {
		return nil
	}
	db.provAvail = map[string][]provider{}
	srcs, _ := LoadSources()
	missing := 0
	for _, s := range srcs {
		f, err := os.Open(s.indexPath(cfg.Arch))
		if err != nil {
			missing++
			continue
		}
		zr, err := gzip.NewReader(bufio.NewReaderSize(f, 1<<16))
		if err != nil {
			f.Close()
			continue
		}
		src := s
		ParseParagraphs(zr, nil, func(p *Paragraph) error {
			pk := newPkg(p)
			if !pk.archOK() {
				return nil
			}
			pk.Src = src
			db.addAvail(pk)
			return nil
		})
		f.Close()
	}
	for _, vs := range db.Avail {
		sort.SliceStable(vs, func(i, j int) bool { return CompareVersions(vs[i].Version, vs[j].Version) > 0 })
	}
	if missing == len(srcs) && len(srcs) > 0 {
		warn("package lists are missing; run 'apt update'")
	}
	return nil
}

func (db *DB) addAvail(pk *Pkg) {
	for _, x := range db.Avail[pk.Name] {
		if x.Version == pk.Version && x.Arch == pk.Arch {
			return
		}
	}
	db.Avail[pk.Name] = append(db.Avail[pk.Name], pk)
	if strings.Contains(pk.P.Get("Provides"), "") && pk.P.Get("Provides") != "" {
		for _, pv := range pk.Provides() {
			db.provAvail[pv.Name] = append(db.provAvail[pv.Name], provider{pk, pv.Ver})
		}
	}
}

func statusPath() string  { return filepath.Join(cfg.Admin, "status") }
func infoDir() string     { return filepath.Join(cfg.Admin, "info") }
func extStatePath() string { return filepath.Join(cfg.Root, "var/lib/apt/extended_states") }

func (db *DB) loadStatus() error {
	f, err := os.Open(statusPath())
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	defer f.Close()
	return ParseParagraphs(f, nil, func(p *Paragraph) error {
		pk := newPkg(p)
		inst := &Installed{Pkg: pk, Status: p.Get("Status")}
		if inst.State() == "not-installed" || inst.State() == "config-files" && false {
			return nil
		}
		key := pk.InfoName()
		if _, dup := db.Installed[key]; !dup {
			db.Order = append(db.Order, key)
		}
		db.Installed[key] = inst
		return nil
	})
}

func (db *DB) SaveStatus() error {
	os.MkdirAll(cfg.Admin, 0755)
	tmp := statusPath() + "-new"
	f, err := os.Create(tmp)
	if err != nil {
		return err
	}
	w := bufio.NewWriter(f)
	keys := make([]string, 0, len(db.Installed))
	for k := range db.Installed {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		db.Installed[k].P.Write822(w)
		w.WriteString("\n")
	}
	w.Flush()
	f.Sync()
	f.Close()
	if _, err := os.Stat(statusPath()); err == nil {
		os.Remove(statusPath() + "-old")
		os.Link(statusPath(), statusPath()+"-old")
	}
	return os.Rename(tmp, statusPath())
}

func (db *DB) loadAuto() {
	f, err := os.Open(extStatePath())
	if err != nil {
		return
	}
	defer f.Close()
	ParseParagraphs(f, nil, func(p *Paragraph) error {
		if p.Get("Auto-Installed") == "1" {
			db.Auto[p.Get("Package")] = true
		}
		return nil
	})
}

func (db *DB) SaveAuto() error {
	os.MkdirAll(filepath.Dir(extStatePath()), 0755)
	var b strings.Builder
	for _, k := range sortedKeys(db.Auto) {
		if db.Auto[k] && db.lookupInstalled(k) != nil {
			fmt.Fprintf(&b, "Package: %s\nArchitecture: %s\nAuto-Installed: 1\n\n", k, cfg.Arch)
		}
	}
	return os.WriteFile(extStatePath(), []byte(b.String()), 0644)
}

func (db *DB) lookupInstalled(name string) *Installed {
	if i, ok := db.Installed[name]; ok {
		return i
	}
	// "pkg:amd64", "pkg:all", "pkg:any" (as passed by py3compile, dh helpers)
	if base, arch, ok := strings.Cut(name, ":"); ok && (arch == cfg.Arch || arch == "all" || arch == "any") {
		if i, ok := db.Installed[base]; ok {
			return i
		}
		name = base
	}
	if i, ok := db.Installed[name+":"+cfg.Arch]; ok {
		return i
	}
	if i, ok := db.Installed[name+":all"]; ok {
		return i
	}
	return nil
}

// Candidate returns the newest available version of name.
func (db *DB) Candidate(name string) *Pkg {
	vs := db.Avail[name]
	if len(vs) == 0 {
		return nil
	}
	return vs[0]
}

// Upgradable lists installed packages that have a newer candidate.
func (db *DB) Upgradable() []*Pkg {
	db.LoadAvailable()
	var out []*Pkg
	for _, k := range sortedKeys(db.Installed) {
		in := db.Installed[k]
		if in.State() != "installed" {
			continue
		}
		if c := db.Candidate(in.Name); c != nil && CompareVersions(c.Version, in.Version) > 0 {
			out = append(out, c)
		}
	}
	return out
}

// installedFiles returns path->owner for all installed packages.
func (db *DB) installedFiles() map[string]string {
	owners := map[string]string{}
	for k := range db.Installed {
		for _, f := range readList(k) {
			if _, ok := owners[f]; !ok {
				owners[f] = k
			} else if owners[f] != k {
				owners[f] += ", " + k
			}
		}
	}
	return owners
}

func readList(infoName string) []string {
	data, err := os.ReadFile(filepath.Join(infoDir(), infoName+".list"))
	if err != nil {
		return nil
	}
	var out []string
	for _, l := range strings.Split(string(data), "\n") {
		if l != "" {
			out = append(out, l)
		}
	}
	return out
}

func writeList(infoName string, files []string) error {
	os.MkdirAll(infoDir(), 0755)
	return os.WriteFile(filepath.Join(infoDir(), infoName+".list"), []byte(strings.Join(files, "\n")+"\n"), 0644)
}

func warn(f string, a ...any) { fmt.Fprintf(os.Stderr, "W: "+f+"\n", a...) }

// baseVirtual returns a synthetic status entry for a package the KwickOS
// base provides virtually (e.g. coreutils), so `dpkg-query -W coreutils`
// and `dpkg -s base-files` behave as maintainer scripts expect.
func (db *DB) baseVirtual(name string) *Installed {
	for _, in := range db.Installed {
		if in.Field("X-Kwick-Base") != "yes" {
			continue
		}
		for _, pv := range in.Provides() {
			if pv.Name == name {
				p := NewParagraph()
				p.Set("Package", name)
				p.Set("Status", "install ok installed")
				p.Set("Architecture", in.Arch)
				ver := pv.Ver
				if ver == "" {
					ver = in.Version
				}
				p.Set("Version", ver)
				p.Set("Description", "provided by "+in.Name)
				return &Installed{Pkg: &Pkg{P: p, Name: name, Version: ver, Arch: in.Arch}, Status: "install ok installed"}
			}
		}
	}
	return nil
}
