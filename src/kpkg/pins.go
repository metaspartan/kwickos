package main

import (
	"fmt"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"unicode"
)

type ReleaseInfo struct {
	Origin, Label, Archive, Codename, Version string
	NotAuto, ButAuto                          bool
}

type fileMeta struct {
	ReleaseInfo
	Comp, Host string
	Known      bool
	Status     bool
}

type pinStanza struct {
	names []string
	kind  string
	data  string
	prio  int
}

func (ps *pinStanza) star() bool {
	return len(ps.names) == 1 && ps.names[0] == "*"
}

func (ps *pinStanza) matchName(name string) bool {
	for _, n := range ps.names {
		if n == "*" || globMatch(n, name) {
			return true
		}
	}
	return false
}

type Policy struct {
	pins   []pinStanza
	defRel string
	meta   map[*Source]*fileMeta
	status fileMeta
}

func globMatch(pat, s string) bool {
	if len(pat) >= 2 && pat[0] == '/' && pat[len(pat)-1] == '/' {
		re, err := regexp.Compile("(?i)" + pat[1:len(pat)-1])
		return err == nil && re.MatchString(s)
	}
	ok, err := path.Match(strings.ToLower(pat), strings.ToLower(s))
	if err != nil {
		return strings.EqualFold(pat, s)
	}
	return ok
}

func hostOf(uri string) string {
	_, h, ok := strings.Cut(uri, "://")
	if !ok {
		return ""
	}
	if i := strings.IndexAny(h, "/?#"); i >= 0 {
		h = h[:i]
	}
	if i := strings.LastIndexByte(h, '@'); i >= 0 {
		h = h[i+1:]
	}
	if strings.HasPrefix(h, "[") {
		if i := strings.IndexByte(h, ']'); i > 0 {
			return h[1:i]
		}
		return ""
	}
	if i := strings.IndexByte(h, ':'); i >= 0 {
		h = h[:i]
	}
	return h
}

func readReleaseInfo(s *Source) (ReleaseInfo, bool) {
	data, err := os.ReadFile(filepath.Join(cfg.Lists, s.base()+"_InRelease"))
	if err != nil {
		return ReleaseInfo{}, false
	}
	text := string(data)
	if strings.HasPrefix(text, "-----BEGIN PGP SIGNED") {
		text = stripClearsign(text)
	}
	var out ReleaseInfo
	found := false
	ParseParagraphs(strings.NewReader(text), nil, func(p *Paragraph) error {
		out = ReleaseInfo{
			Origin: p.Get("Origin"), Label: p.Get("Label"), Archive: p.Get("Suite"),
			Codename: p.Get("Codename"), Version: p.Get("Version"),
			NotAuto: strings.EqualFold(p.Get("NotAutomatic"), "yes"),
			ButAuto: strings.EqualFold(p.Get("ButAutomaticUpgrades"), "yes"),
		}
		found = true
		return errStopParse
	})
	return out, found
}

var errStopParse = fmt.Errorf("stop")

func (pl *Policy) metaOf(s *Source) *fileMeta {
	if m, ok := pl.meta[s]; ok {
		return m
	}
	m := &fileMeta{Comp: s.Comp, Host: hostOf(s.URI)}
	if ri, ok := readReleaseInfo(s); ok {
		m.ReleaseInfo = ri
		m.Known = true
	} else {
		m.Archive, m.Codename = s.Suite, s.Suite
	}
	if pl.meta == nil {
		pl.meta = map[*Source]*fileMeta{}
	}
	pl.meta[s] = m
	return m
}

func (m *fileMeta) matchRelease(data, arch string) bool {
	data = strings.Trim(strings.TrimSpace(data), `"`)
	if data == "" {
		return false
	}
	if !strings.Contains(data, "=") {
		if globMatch(data, m.Archive) || globMatch(data, m.Codename) {
			return true
		}
		return unicode.IsDigit(rune(data[0])) && m.Version != "" && globMatch(data, m.Version)
	}
	for _, kv := range strings.Split(data, ",") {
		k, v, ok := strings.Cut(strings.TrimSpace(kv), "=")
		if !ok {
			return false
		}
		var have string
		switch strings.ToLower(strings.TrimSpace(k)) {
		case "a":
			have = m.Archive
		case "n":
			have = m.Codename
		case "v":
			have = m.Version
		case "o":
			have = m.Origin
		case "l":
			have = m.Label
		case "c":
			have = m.Comp
		case "b":
			have = arch
		default:
			return false
		}
		v = strings.TrimSpace(v)
		if v == "" || !globMatch(v, have) {
			return false
		}
	}
	return true
}

func (m *fileMeta) matches(kind, data, arch string) bool {
	switch kind {
	case "release":
		return m.matchRelease(data, arch)
	case "origin":
		return globMatch(strings.Trim(strings.TrimSpace(data), `"`), m.Host)
	}
	return false
}

func splitPinNames(v string) []string {
	return strings.FieldsFunc(v, func(r rune) bool { return r == ' ' || r == ',' || r == '\t' })
}

func parsePrefs(data string) []pinStanza {
	var out []pinStanza
	ParseParagraphs(strings.NewReader(data), nil, func(p *Paragraph) error {
		names := splitPinNames(p.Get("Package"))
		pin := strings.TrimSpace(p.Get("Pin"))
		prio, err := strconv.Atoi(strings.TrimSpace(p.Get("Pin-Priority")))
		if len(names) == 0 || pin == "" || err != nil || prio == 0 {
			return nil
		}
		kind, rest, _ := strings.Cut(pin, " ")
		kind = strings.ToLower(kind)
		rest = strings.TrimSpace(rest)
		ps := pinStanza{names: names, kind: kind, data: strings.Trim(rest, `"`), prio: prio}
		if (kind != "release" && kind != "origin" && kind != "version") || (kind == "version" && ps.star()) {
			warn("Did not understand pin type %s", kind)
			return nil
		}
		out = append(out, ps)
		return nil
	})
	return out
}

func readAptConf(data string, out map[string]string) {
	var scope []string
	var toks []string
	i := 0
	flush := func() {
		toks = toks[:0]
	}
	for i < len(data) {
		c := data[i]
		switch {
		case c == ' ' || c == '\t' || c == '\n' || c == '\r':
			i++
		case c == '#' && (i == 0 || data[i-1] == '\n'):
			for i < len(data) && data[i] != '\n' {
				i++
			}
		case strings.HasPrefix(data[i:], "//"):
			for i < len(data) && data[i] != '\n' {
				i++
			}
		case strings.HasPrefix(data[i:], "/*"):
			j := strings.Index(data[i+2:], "*/")
			if j < 0 {
				return
			}
			i += j + 4
		case c == '"':
			j := i + 1
			for j < len(data) && data[j] != '"' {
				j++
			}
			toks = append(toks, `"`+data[i+1:min(j, len(data))])
			i = j + 1
		case c == '{':
			if len(toks) > 0 {
				scope = append(scope, toks[0])
			} else {
				scope = append(scope, "")
			}
			flush()
			i++
		case c == '}':
			if len(scope) > 0 {
				scope = scope[:len(scope)-1]
			}
			flush()
			i++
		case c == ';':
			if len(toks) >= 2 && strings.HasPrefix(toks[len(toks)-1], `"`) {
				key := strings.Join(append(append([]string{}, scope...), toks[0]), "::")
				out[strings.ToLower(strings.Trim(key, ":"))] = toks[len(toks)-1][1:]
			}
			flush()
			i++
		default:
			j := i
			for j < len(data) && !strings.ContainsRune(" \t\r\n{};\"", rune(data[j])) {
				j++
			}
			toks = append(toks, data[i:j])
			i = j
		}
	}
}

func LoadPolicy() *Policy {
	pl := &Policy{status: fileMeta{ReleaseInfo: ReleaseInfo{Archive: "now"}, Status: true}}
	files := []string{filepath.Join(cfg.Root, "etc/apt/preferences")}
	ents, _ := os.ReadDir(filepath.Join(cfg.Root, "etc/apt/preferences.d"))
	for _, e := range ents {
		ext := filepath.Ext(e.Name())
		if e.IsDir() || (ext != "" && ext != ".pref") || strings.HasPrefix(e.Name(), ".") {
			continue
		}
		files = append(files, filepath.Join(cfg.Root, "etc/apt/preferences.d", e.Name()))
	}
	for _, f := range files {
		if data, err := os.ReadFile(f); err == nil {
			pl.pins = append(pl.pins, parsePrefs(string(data))...)
		}
	}
	conf := map[string]string{}
	cfiles := []string{filepath.Join(cfg.Root, "etc/apt/apt.conf")}
	cents, _ := os.ReadDir(filepath.Join(cfg.Root, "etc/apt/apt.conf.d"))
	for _, e := range cents {
		if !e.IsDir() && !strings.HasPrefix(e.Name(), ".") && !strings.HasSuffix(e.Name(), "~") {
			cfiles = append(cfiles, filepath.Join(cfg.Root, "etc/apt/apt.conf.d", e.Name()))
		}
	}
	for _, f := range cfiles {
		if data, err := os.ReadFile(f); err == nil {
			readAptConf(string(data), conf)
		}
	}
	pl.defRel = conf["apt::default-release"]
	if cfg.TargetRelease != "" {
		pl.defRel = cfg.TargetRelease
	}
	return pl
}

func pkgArch(pk *Pkg) string {
	if pk.Arch == "all" {
		return cfg.Arch
	}
	return pk.Arch
}

func (pl *Policy) filePrio(s *Source, arch string) int {
	m := pl.metaOf(s)
	if pl.defRel != "" && m.matchRelease(pl.defRel, arch) {
		return 990
	}
	for i := range pl.pins {
		ps := &pl.pins[i]
		if ps.star() && ps.kind != "version" && m.matches(ps.kind, ps.data, arch) {
			return ps.prio
		}
	}
	if m.NotAuto {
		if m.ButAuto {
			return 100
		}
		return 1
	}
	return 500
}

func (pk *Pkg) sources() []*Source {
	if pk.Src == nil {
		return nil
	}
	return append([]*Source{pk.Src}, pk.Also...)
}

func (db *DB) installedSame(pk *Pkg) bool {
	in := db.Installed[pk.InfoName()]
	if in == nil {
		in = db.lookupInstalled(pk.Key())
	}
	return in != nil && in.Key() == pk.Key() && in.Version == pk.Version && in.State() != "not-installed" && in.State() != "config-files"
}

func (db *DB) policy() *Policy {
	if db.Pol == nil {
		db.Pol = LoadPolicy()
	}
	return db.Pol
}

func (db *DB) Prio(pk *Pkg) int {
	if pk.LocalDeb != "" {
		return 1 << 20
	}
	pl := db.policy()
	arch := pkgArch(pk)
	inst := db.installedSame(pk)
	for i := range pl.pins {
		ps := &pl.pins[i]
		if ps.star() || !ps.matchName(pk.Name) {
			continue
		}
		if ps.kind == "version" {
			if globMatch(ps.data, pk.Version) {
				return ps.prio
			}
			continue
		}
		for _, s := range pk.sources() {
			if pl.metaOf(s).matches(ps.kind, ps.data, arch) {
				return ps.prio
			}
		}
		if inst && pl.status.matches(ps.kind, ps.data, arch) {
			return ps.prio
		}
	}
	best := -1 << 31
	for _, s := range pk.sources() {
		best = max(best, pl.filePrio(s, arch))
	}
	if pk.Src == nil {
		best = 500
	}
	if inst {
		best = max(best, 100)
	}
	return best
}

type rankedPkg struct {
	pk   *Pkg
	prio int
}

func (db *DB) rank(key string) []rankedPkg {
	var out []rankedPkg
	for _, pk := range db.Avail[key] {
		if pr := db.Prio(pk); pr >= 0 {
			out = append(out, rankedPkg{pk, pr})
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].prio != out[j].prio {
			return out[i].prio > out[j].prio
		}
		return CompareVersions(out[i].pk.Version, out[j].pk.Version) > 0
	})
	return out
}

func (db *DB) Ranked(key string) []*Pkg {
	rs := db.rank(key)
	out := make([]*Pkg, len(rs))
	for i, r := range rs {
		out[i] = r.pk
	}
	return out
}

func (db *DB) pickCandidate(key string) *Pkg {
	c := db.freeCandidate(key)
	in := db.installedByKey(key)
	if c == nil || in == nil || !in.Held() || cfg.AllowHeld || c.Version == in.Version {
		return c
	}
	for _, r := range db.rank(key) {
		if r.pk.Version == in.Version {
			return r.pk
		}
	}
	if in.State() == "installed" {
		return in.Pkg
	}
	return nil
}

func (db *DB) holdBlocks(p *Pkg) bool {
	if cfg.AllowHeld {
		return false
	}
	in := db.installedByKey(p.Key())
	return in != nil && in.Held() && in.Version != p.Version
}

func (db *DB) freeCandidate(key string) *Pkg {
	rs := db.rank(key)
	in := db.lookupInstalled(key)
	if in != nil && (in.Key() != key || in.State() == "not-installed" || in.State() == "config-files") {
		in = nil
	}
	for _, r := range rs {
		if r.prio <= 0 {
			continue
		}
		if in != nil && r.prio < 1000 && CompareVersions(r.pk.Version, in.Version) < 0 {
			continue
		}
		return r.pk
	}
	return nil
}

func (db *DB) Newest(key string) *Pkg {
	if c := db.Candidate(key); c != nil {
		return c
	}
	if vs := db.Avail[key]; len(vs) > 0 {
		return vs[0]
	}
	return nil
}

func (db *DB) srcMatchesRelease(s *Source, name string) bool {
	if s.Suite == name {
		return true
	}
	m := db.policy().metaOf(s)
	return m.matchRelease(name, "")
}

func (db *DB) srcMatchesAny(p *Pkg, name string) bool {
	for _, s := range p.sources() {
		if db.srcMatchesRelease(s, name) {
			return true
		}
	}
	return false
}

func (pl *Policy) label(s *Source) string {
	m := pl.metaOf(s)
	if !m.Known {
		return s.Suite + "/" + s.Comp
	}
	if m.Version == "" {
		return m.Origin + ":" + m.Archive
	}
	return m.Origin + ":" + m.Version + "/" + m.Archive
}

func srcLabel(p *Pkg) string {
	srcs := p.sources()
	if len(srcs) == 0 {
		return "local"
	}
	pl := &Policy{}
	if curDB != nil {
		pl = curDB.policy()
	}
	var parts []string
	seen := map[string]bool{}
	for _, s := range srcs {
		l := pl.label(s)
		if !seen[l] {
			seen[l] = true
			parts = append(parts, l)
		}
	}
	return strings.Join(parts, ", ")
}

func (pl *Policy) releaseLine(m *fileMeta, arch string) string {
	var parts []string
	add := func(k, v string) {
		if v != "" {
			parts = append(parts, k+"="+v)
		}
	}
	add("v", m.Version)
	add("o", m.Origin)
	add("a", m.Archive)
	add("n", m.Codename)
	add("l", m.Label)
	add("c", m.Comp)
	add("b", arch)
	return strings.Join(parts, ",")
}

func policyIndexArch(s *Source) string {
	for _, a := range allArches() {
		if len(s.Arches) > 0 && !contains(s.Arches, a) {
			continue
		}
		if _, err := os.Stat(s.indexPath(a)); err == nil {
			return a
		}
	}
	return cfg.Arch
}

func fileURL(s *Source) string {
	return strings.TrimRight(s.URI, "/") + " " + s.Suite + "/" + s.Comp
}

func printPolicyAll(db *DB) {
	pl := db.policy()
	srcs, _ := LoadSources()
	sort.SliceStable(srcs, func(i, j int) bool {
		pi, pj := pl.filePrio(srcs[i], cfg.Arch), pl.filePrio(srcs[j], cfg.Arch)
		if pi != pj {
			return pi > pj
		}
		return srcs[i].base()+"_"+srcs[i].Comp < srcs[j].base()+"_"+srcs[j].Comp
	})
	fmt.Println("Package files:")
	fmt.Println(" 100 " + filepath.Join("/", "var/lib/dpkg/status"))
	fmt.Println("     release a=now")
	for _, s := range srcs {
		arch := policyIndexArch(s)
		if _, err := os.Stat(s.indexPath(arch)); err != nil {
			continue
		}
		m := pl.metaOf(s)
		fmt.Printf(" %d %s %s Packages\n", pl.filePrio(s, arch), fileURL(s), arch)
		if m.Known {
			fmt.Printf("     release %s\n", pl.releaseLine(m, arch))
		} else {
			fmt.Printf("     release a=%s,n=%s,c=%s,b=%s\n", s.Suite, s.Suite, s.Comp, arch)
		}
		if m.Host != "" {
			fmt.Printf("     origin %s\n", m.Host)
		}
	}
	fmt.Println("Pinned packages:")
	for i := range pl.pins {
		ps := &pl.pins[i]
		if ps.star() {
			continue
		}
		for _, n := range sortedKeys(db.Avail) {
			if !ps.matchName(db.Avail[n][0].Name) {
				continue
			}
			for _, pk := range db.Avail[n] {
				if db.effectivePin(pk) == ps {
					fmt.Printf("     %s -> %s with priority %d\n", pk.Name, pk.Version, ps.prio)
				}
			}
		}
	}
}

func (db *DB) effectivePin(pk *Pkg) *pinStanza {
	pl := db.policy()
	arch := pkgArch(pk)
	inst := db.installedSame(pk)
	for i := range pl.pins {
		ps := &pl.pins[i]
		if ps.star() || !ps.matchName(pk.Name) {
			continue
		}
		if ps.kind == "version" {
			if globMatch(ps.data, pk.Version) {
				return ps
			}
			continue
		}
		for _, s := range pk.sources() {
			if pl.metaOf(s).matches(ps.kind, ps.data, arch) {
				return ps
			}
		}
		if inst && pl.status.matches(ps.kind, ps.data, arch) {
			return ps
		}
	}
	return nil
}

func printPolicy(db *DB, name string) {
	key := name
	vs := db.Avail[key]
	in := db.lookupInstalled(name)
	if in != nil && in.State() == "not-installed" {
		in = nil
	}
	if len(vs) == 0 && in == nil {
		if _, ok := db.provAvail[name]; !ok {
			return
		}
	}
	pl := db.policy()
	fmt.Printf("%s:\n", name)
	iv, cv := "(none)", "(none)"
	if in != nil {
		iv = in.Version
	}
	if c := db.Candidate(key); c != nil {
		cv = c.Version
	} else if in != nil {
		cv = in.Version
	}
	fmt.Printf("  Installed: %s\n  Candidate: %s\n  Version table:\n", iv, cv)
	rows := append([]*Pkg{}, vs...)
	instListed := false
	for _, p := range rows {
		if in != nil && p.Version == in.Version {
			instListed = true
		}
	}
	if in != nil && !instListed {
		rows = append(rows, in.Pkg)
		sort.SliceStable(rows, func(i, j int) bool { return CompareVersions(rows[i].Version, rows[j].Version) > 0 })
	}
	for _, p := range rows {
		mark := "    "
		if in != nil && p.Version == in.Version {
			mark = "*** "
		}
		pr := db.Prio(p)
		if in != nil && p == in.Pkg && p.Src == nil {
			pr = 100
		}
		fmt.Printf(" %s%s %d\n", mark, p.Version, pr)
		for _, s := range p.sources() {
			arch := policyIndexArch(s)
			fmt.Printf("%11d %s %s Packages\n", pl.filePrio(s, pkgArch(p)), fileURL(s), arch)
		}
		if in != nil && p.Version == in.Version {
			fmt.Printf("%11d /var/lib/dpkg/status\n", 100)
		}
	}
}

func printMadison(db *DB, name string) {
	for _, p := range db.Avail[name] {
		for _, s := range p.sources() {
			fmt.Printf("%10s | %10s | %s %s/%s %s Packages\n", p.Name, p.Version, strings.TrimRight(s.URI, "/"), s.Suite, s.Comp, policyIndexArch(s))
		}
	}
}
