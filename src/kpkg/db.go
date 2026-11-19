package main

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"unsafe"

	"github.com/klauspost/compress/gzip"
)

type Pkg struct {
	P        *Paragraph
	Name     string
	Version  string
	Arch     string
	Src      *Source
	LocalDeb string
	Also     []*Source
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
		d = ParseDeps(p.P.Get(field), p.selfArch())
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

func (p *Pkg) Size() int64 { n, _ := strconv.ParseInt(p.Field("Size"), 10, 64); return n }
func (p *Pkg) InstalledSize() int64 {
	n, _ := strconv.ParseInt(p.Field("Installed-Size"), 10, 64)
	return n * 1024
}
func (p *Pkg) Essential() bool     { return p.Field("Essential") == "yes" || p.Field("Protected") == "yes" }
func (p *Pkg) MultiArchSame() bool { return p.Field("Multi-Arch") == "same" }

func (p *Pkg) InfoName() string { return infoNameFor(p.Name, p.Arch, p.MultiArch()) }

func (p *Pkg) archOK() bool {
	return p.Arch == cfg.Arch || p.Arch == "all" || contains(cfg.Foreign, p.Arch)
}

type Installed struct {
	*Pkg
	Status string
}

func (i *Installed) State() string {
	f := strings.Fields(i.Status)
	if len(f) == 3 {
		return f[2]
	}
	return ""
}

func (i *Installed) Held() bool {
	return strings.HasPrefix(i.Status, "hold ")
}

func (i *Installed) setState(want, state string) {
	if want == "install" && i.Held() {
		want = "hold"
	}
	i.Status = want + " ok " + state
	i.P.Set("Status", i.Status)
}

type provider struct {
	pkg *Pkg
	ver string
}

type DB struct {
	Avail     map[string][]*Pkg
	Installed map[string]*Installed
	Order     []string
	provAvail map[string][]provider
	Auto      map[string]bool
	Pol       *Policy
	cand      map[string]*Pkg
}

var curDB *DB

func OpenDB() (*DB, error) {
	db := &DB{Avail: map[string][]*Pkg{}, Installed: map[string]*Installed{}, Auto: map[string]bool{}}
	if err := db.loadStatus(); err != nil {
		return nil, err
	}
	db.loadAuto()
	curDB = db
	return db, nil
}

type idxJob struct {
	src  *Source
	path string
	pkgs []*Pkg
}

func readKidx(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	zr, err := gzip.NewReader(bytes.NewReader(data))
	if err != nil {
		return "", err
	}
	defer zr.Close()
	var out []byte
	if n := len(data); n >= 18 {
		isize := int(binary.LittleEndian.Uint32(data[n-4:]))
		if isize >= n && isize < 1<<30 {
			out = make([]byte, isize)
			got, err := io.ReadFull(zr, out)
			out = out[:got]
			if err != nil && err != io.ErrUnexpectedEOF {
				return "", err
			}
			if err == nil {
				rest, err := io.ReadAll(zr)
				if err != nil {
					return "", err
				}
				out = append(out, rest...)
			}
		}
	}
	if out == nil {
		if out, err = io.ReadAll(zr); err != nil {
			return "", err
		}
	}
	if len(out) == 0 {
		return "", nil
	}
	return unsafe.String(unsafe.SliceData(out), len(out)), nil
}

func splitParagraphChunks(s string, n int) []string {
	if n < 2 || len(s) < 1<<20 {
		return []string{s}
	}
	var out []string
	size := len(s) / n
	start := 0
	for len(out) < n-1 {
		cut := start + size
		if cut >= len(s) {
			break
		}
		j := strings.Index(s[cut:], "\n\n")
		if j < 0 {
			break
		}
		end := cut + j + 1
		out = append(out, s[start:end])
		start = end
	}
	return append(out, s[start:])
}

func parseIndexPkgs(s string, src *Source) []*Pkg {
	chunks := splitParagraphChunks(s, runtime.GOMAXPROCS(0))
	parts := make([][]*Pkg, len(chunks))
	var wg sync.WaitGroup
	for i, c := range chunks {
		wg.Add(1)
		go func() {
			defer wg.Done()
			var pkgs []*Pkg
			parseParagraphString(c, nil, func(p *Paragraph) error {
				pk := newPkg(p)
				if !pk.archOK() {
					return nil
				}
				pk.Src = src
				if p.Get("Provides") != "" {
					pk.Provides()
				}
				pkgs = append(pkgs, pk)
				return nil
			})
			parts[i] = pkgs
		}()
	}
	wg.Wait()
	if len(parts) == 1 {
		return parts[0]
	}
	total := 0
	for _, p := range parts {
		total += len(p)
	}
	all := make([]*Pkg, 0, total)
	for _, p := range parts {
		all = append(all, p...)
	}
	return all
}

func (db *DB) LoadAvailable() error {
	if db.provAvail != nil {
		return nil
	}
	db.provAvail = map[string][]provider{}
	srcs, _ := LoadSources()
	missing := 0
	var jobs []*idxJob
	for _, s := range srcs {
		found := false
		for _, arch := range allArches() {
			if len(s.Arches) > 0 && !contains(s.Arches, arch) {
				continue
			}
			p := s.indexPath(arch)
			if _, err := os.Stat(p); err != nil {
				continue
			}
			found = true
			jobs = append(jobs, &idxJob{src: s, path: p})
		}
		if !found {
			missing++
		}
	}
	var wg sync.WaitGroup
	for _, j := range jobs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			s, err := readKidx(j.path)
			if err != nil || s == "" {
				return
			}
			j.pkgs = parseIndexPkgs(s, j.src)
		}()
	}
	wg.Wait()
	for _, j := range jobs {
		for _, pk := range j.pkgs {
			db.addAvail(pk)
		}
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
	key := pk.Key()
	db.cand = nil
	for _, x := range db.Avail[key] {
		if x.Version == pk.Version && x.Arch == pk.Arch {
			if pk.Src != nil && x.Src != nil && x.Src != pk.Src {
				x.Also = append(x.Also, pk.Src)
			}
			return
		}
	}
	db.Avail[key] = append(db.Avail[key], pk)
	if strings.Contains(pk.P.Get("Provides"), "") && pk.P.Get("Provides") != "" {
		for _, pv := range pk.Provides() {
			db.provAvail[pv.Name] = append(db.provAvail[pv.Name], provider{pk, pv.Ver})
		}
	}
}

func statusPath() string   { return filepath.Join(cfg.Admin, "status") }
func infoDir() string      { return filepath.Join(cfg.Admin, "info") }
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
	w := bufio.NewWriterSize(f, 1<<16)
	for _, k := range sortedKeys(db.Installed) {
		db.Installed[k].P.Write822(w)
		w.WriteString("\n")
	}
	err = w.Flush()
	if err == nil {
		err = f.Sync()
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		os.Remove(tmp)
		return fmt.Errorf("unable to write %s: %v", statusPath(), err)
	}
	if _, err := os.Stat(statusPath()); err == nil {
		os.Remove(statusPath() + "-old")
		os.Link(statusPath(), statusPath()+"-old")
	}
	return os.Rename(tmp, statusPath())
}

func writeFileAtomic(name string, data []byte, perm os.FileMode, sync bool) error {
	tmp := name + "-new"
	f, err := os.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, perm)
	if err != nil {
		return err
	}
	_, err = f.Write(data)
	if err == nil && sync {
		err = f.Sync()
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, name)
}

func (db *DB) loadAuto() {
	f, err := os.Open(extStatePath())
	if err != nil {
		return
	}
	defer f.Close()
	ParseParagraphs(f, nil, func(p *Paragraph) error {
		if p.Get("Auto-Installed") == "1" {
			db.Auto[keyOf(p.Get("Package"), p.Get("Architecture"))] = true
		}
		return nil
	})
}

func (db *DB) SaveAuto() error {
	os.MkdirAll(filepath.Dir(extStatePath()), 0755)
	var b strings.Builder
	for _, k := range sortedKeys(db.Auto) {
		if db.Auto[k] && db.installedByKey(k) != nil {
			n, a := splitKey(k)
			if a == "" {
				a = cfg.Arch
			}
			fmt.Fprintf(&b, "Package: %s\nArchitecture: %s\nAuto-Installed: 1\n\n", n, a)
		}
	}
	return writeFileAtomic(extStatePath(), []byte(b.String()), 0644, true)
}

func (db *DB) lookupInstalled(name string) *Installed {
	if i, ok := db.Installed[name]; ok {
		return i
	}
	base, arch, qualified := strings.Cut(name, ":")
	if qualified {
		switch {
		case arch == "any" || arch == "all" || arch == "native":
			if arch == "native" {
				arch = cfg.Arch
			}
		case knownArch(arch):
		default:
			return nil
		}
		if arch == "any" || arch == "all" {
			if i := db.lookupInstalled(base); i != nil {
				return i
			}
			for _, a := range cfg.Foreign {
				if i := db.lookupInstalled(base + ":" + a); i != nil {
					return i
				}
			}
			return nil
		}
		for _, k := range []string{base + ":" + arch, base} {
			if i, ok := db.Installed[k]; ok && (i.Arch == arch || i.Arch == "all") {
				return i
			}
		}
		return nil
	}
	for _, k := range []string{name + ":" + cfg.Arch, name + ":all"} {
		if i, ok := db.Installed[k]; ok {
			return i
		}
	}
	for _, a := range cfg.Foreign {
		if i, ok := db.Installed[name+":"+a]; ok {
			return i
		}
	}
	return nil
}

func (db *DB) Candidate(name string) *Pkg {
	if db.cand == nil {
		db.cand = map[string]*Pkg{}
	}
	if c, ok := db.cand[name]; ok {
		return c
	}
	c := db.pickCandidate(name)
	db.cand[name] = c
	return c
}

func (db *DB) Upgradable() []*Pkg {
	db.LoadAvailable()
	var out []*Pkg
	for _, k := range sortedKeys(db.Installed) {
		in := db.Installed[k]
		if in.State() != "installed" {
			continue
		}
		if c := db.Candidate(in.Key()); c != nil && CompareVersions(c.Version, in.Version) != 0 {
			out = append(out, c)
		}
	}
	return out
}

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
	return writeFileAtomic(filepath.Join(infoDir(), infoName+".list"), []byte(strings.Join(files, "\n")+"\n"), 0644, false)
}

func warn(f string, a ...any) { fmt.Fprintf(os.Stderr, "W: "+f+"\n", a...) }

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
