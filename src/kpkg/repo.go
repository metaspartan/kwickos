package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

type Source struct {
	URI, Suite, Comp string
	SignedBy         []string
	Trusted          bool
	Arches           []string
}

func (s *Source) base() string {
	u := s.URI
	if i := strings.Index(u, "://"); i >= 0 {
		u = u[i+3:]
	}
	u = strings.TrimRight(u, "/")
	return strings.ReplaceAll(u, "/", "_") + "_dists_" + strings.ReplaceAll(s.Suite, "/", "_")
}

func (s *Source) indexPath(arch string) string {
	return filepath.Join(cfg.Lists, s.base()+"_"+s.Comp+"_binary-"+arch+"_Packages.kidx")
}

func (s *Source) label() string {
	u := strings.TrimRight(s.URI, "/")
	return u + " " + s.Suite
}

func LoadSources() ([]*Source, error) {
	var out []*Source
	files := []string{filepath.Join(cfg.Root, "etc/apt/sources.list")}
	ents, _ := os.ReadDir(filepath.Join(cfg.Root, "etc/apt/sources.list.d"))
	for _, e := range ents {
		files = append(files, filepath.Join(cfg.Root, "etc/apt/sources.list.d", e.Name()))
	}
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		switch {
		case strings.HasSuffix(f, ".sources"):
			ParseParagraphs(strings.NewReader(string(data)), nil, func(p *Paragraph) error {
				if strings.EqualFold(p.Get("Enabled"), "no") || !strings.Contains(" "+p.Get("Types")+" ", " deb ") {
					return nil
				}
				for _, u := range strings.Fields(p.Get("URIs")) {
					for _, su := range strings.Fields(p.Get("Suites")) {
						for _, c := range strings.Fields(p.Get("Components")) {
							s := &Source{URI: u, Suite: su, Comp: c, Arches: strings.Fields(p.Get("Architectures"))}
							if sb := p.Get("Signed-By"); sb != "" {
								s.SignedBy = strings.Fields(sb)
							}
							s.Trusted = strings.EqualFold(p.Get("Trusted"), "yes")
							out = append(out, s)
						}
					}
				}
				return nil
			})
		case strings.HasSuffix(f, ".list") || filepath.Base(f) == "sources.list":
			for _, line := range strings.Split(string(data), "\n") {
				line = strings.TrimSpace(line)
				if i := strings.IndexByte(line, '#'); i >= 0 {
					line = line[:i]
				}
				fs := strings.Fields(line)
				if len(fs) < 3 || fs[0] != "deb" {
					continue
				}
				var opts []string
				if strings.HasPrefix(fs[1], "[") {
					j := 1
					for ; j < len(fs) && !strings.HasSuffix(fs[j], "]"); j++ {
					}
					opts = fs[1 : j+1]
					fs = append([]string{"deb"}, fs[j+1:]...)
				}
				if len(fs) < 3 {
					continue
				}
				for _, c := range fs[3:] {
					s := &Source{URI: fs[1], Suite: fs[2], Comp: c}
					for _, o := range opts {
						o = strings.Trim(o, "[]")
						if v, ok := strings.CutPrefix(o, "signed-by="); ok {
							s.SignedBy = []string{v}
						}
						if o == "trusted=yes" {
							s.Trusted = true
						}
						if v, ok := strings.CutPrefix(o, "arch="); ok {
							s.Arches = strings.Split(v, ",")
						}
					}
					out = append(out, s)
				}
			}
		}
	}
	return out, nil
}

func loadKeyring(paths []string) Keyring {
	kr := Keyring{}
	if len(paths) == 0 {
		for _, pat := range []string{"etc/apt/trusted.gpg.d/*.gpg", "etc/apt/trusted.gpg.d/*.asc", "etc/apt/trusted.gpg", "usr/share/keyrings/kwickos-archive-keyring.*"} {
			m, _ := filepath.Glob(filepath.Join(cfg.Root, pat))
			paths = append(paths, m...)
		}
	}
	for _, p := range paths {
		if !strings.HasPrefix(p, cfg.Root) {
			p = filepath.Join(cfg.Root, p)
		}
		kr.Load(p)
	}
	return kr
}

var indexKeep = map[string]bool{"Package": true, "Version": true, "Architecture": true, "Multi-Arch": true,
	"Essential": true, "Protected": true, "Priority": true, "Section": true, "Installed-Size": true, "Maintainer": true,
	"Depends": true, "Pre-Depends": true, "Recommends": true, "Suggests": true, "Conflicts": true,
	"Breaks": true, "Replaces": true, "Provides": true, "Filename": true, "Size": true, "SHA256": true,
	"Description": true, "Homepage": true, "Source": true, leanField: true}

type relEntry struct {
	hash string
	size int64
}

type progress struct {
	mu sync.Mutex
	n  int
}

func (p *progress) next() int { p.mu.Lock(); defer p.mu.Unlock(); p.n++; return p.n }

func Update() error {
	srcs, _ := LoadSources()
	if len(srcs) == 0 {
		return errors.New("no sources configured in /etc/apt/sources.list(.d)")
	}
	os.MkdirAll(cfg.Lists, 0755)
	groups := map[string][]*Source{}
	var order []string
	for _, s := range srcs {
		k := s.URI + "|" + s.Suite
		if _, ok := groups[k]; !ok {
			order = append(order, k)
		}
		groups[k] = append(groups[k], s)
	}
	start := time.Now()
	var fetched int64
	var mu sync.Mutex
	var errs []string
	pr := &progress{}
	var wg sync.WaitGroup
	for _, k := range order {
		wg.Add(1)
		go func(ss []*Source) {
			defer wg.Done()
			n, err := updateSuite(ss, pr)
			mu.Lock()
			fetched += n
			if err != nil {
				errs = append(errs, err.Error())
			}
			mu.Unlock()
		}(groups[k])
	}
	wg.Wait()
	pruneLists(srcs)
	el := time.Since(start).Seconds()
	if fetched > 0 {
		fmt.Printf("Fetched %s in %.0fs (%s/s)\n", human(fetched), el+0.5, human(int64(float64(fetched)/max(el, 0.001))))
	}
	fmt.Println("Reading package lists... Done")
	if len(errs) > 0 {
		fatal := len(errs) == len(order)
		for _, e := range errs {
			if strings.Contains(e, "not signed") || strings.Contains(e, "mismatch") || strings.Contains(e, "expired") {
				fatal = true
				fmt.Fprintln(os.Stderr, "E:", e)
			} else {
				fmt.Fprintln(os.Stderr, "W: Failed to fetch:", e)
			}
		}
		if fatal {
			return errors.New("some index files failed to download")
		}
	}
	db, err := OpenDB()
	if err == nil {
		up := db.Upgradable()
		if len(up) > 0 {
			fmt.Printf("%d package(s) can be upgraded. Run 'apt list --upgradable' to see them.\n", len(up))
		} else {
			fmt.Println("All packages are up to date.")
		}
	}
	return nil
}

func pruneLists(srcs []*Source) {
	ents, err := os.ReadDir(cfg.Lists)
	if err != nil {
		return
	}
	var keep []string
	for _, s := range srcs {
		keep = append(keep, s.base()+"_")
	}
	for _, e := range ents {
		n := e.Name()
		if !e.Type().IsRegular() || !strings.Contains(n, "_dists_") {
			continue
		}
		known := false
		for _, k := range keep {
			if strings.HasPrefix(n, k) {
				known = true
				break
			}
		}
		if !known {
			os.Remove(filepath.Join(cfg.Lists, n))
		}
	}
}

func updateSuite(ss []*Source, pr *progress) (int64, error) {
	s0 := ss[0]
	base := strings.TrimRight(s0.URI, "/") + "/dists/" + s0.Suite + "/"
	resp, err := httpGet(base + "InRelease")
	if err != nil {
		fmt.Printf("Err:%d %s InRelease\n", pr.next(), s0.label())
		return 0, err
	}
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 64<<20))
	resp.Body.Close()
	if err != nil {
		return 0, err
	}
	fetched := int64(len(raw))
	cached := filepath.Join(cfg.Lists, s0.base()+"_InRelease")
	old, _ := os.ReadFile(cached)
	unchanged := string(old) == string(raw)
	var text string
	if s0.Trusted {
		text = string(raw)
		if strings.HasPrefix(text, "-----BEGIN PGP SIGNED") {
			if t, err := VerifyClearsigned(raw, Keyring{}); err == nil {
				text = t
			} else {
				text = stripClearsign(text)
			}
		}
	} else {
		text, err = VerifyClearsigned(raw, loadKeyring(s0.SignedBy))
		if err != nil {
			fmt.Printf("Err:%d %s InRelease\n", pr.next(), s0.label())
			return fetched, fmt.Errorf("the repository '%s' is not signed by a trusted key: %v", s0.label(), err)
		}
	}
	var rel *Paragraph
	ParseParagraphs(strings.NewReader(text), nil, func(p *Paragraph) error { rel = p; return io.EOF })
	if rel == nil {
		return fetched, fmt.Errorf("%s: empty Release file", s0.label())
	}
	if !checkDist(rel, s0.Suite) {
		return fetched, fmt.Errorf("suite mismatch for %s: expected '%s' but the Release file is for Suite '%s', Codename '%s' (refusing a possible downgrade or replay)", s0.label(), s0.Suite, rel.Get("Suite"), rel.Get("Codename"))
	}
	if vu := rel.Get("Valid-Until"); vu != "" {
		if t, ok := parseRFC1123(vu); ok && time.Now().After(t) {
			return fetched, fmt.Errorf("Release file for %s is expired (invalid since %s)", s0.label(), vu)
		}
	}
	hashes := map[string]relEntry{}
	for _, line := range strings.Split(rel.Get("SHA256"), "\n") {
		f := strings.Fields(line)
		if len(f) == 3 {
			sz, _ := strconv.ParseInt(f[1], 10, 64)
			hashes[f[2]] = relEntry{f[0], sz}
		}
	}
	byHash := strings.EqualFold(rel.Get("Acquire-By-Hash"), "yes")
	allPresent := true
	for _, s := range ss {
		for _, arch := range allArches() {
			if len(s.Arches) > 0 && !contains(s.Arches, arch) {
				continue
			}
			if name, _ := indexEntry(s, arch, hashes); name == "" && len(hashes) > 0 {
				continue
			}
			if _, err := os.Stat(s.indexPath(arch)); err != nil {
				allPresent = false
			}
		}
	}
	if unchanged && allPresent {
		fmt.Printf("Hit:%d %s InRelease\n", pr.next(), s0.label())
		return 0, nil
	}
	fmt.Printf("Get:%d %s InRelease [%s]\n", pr.next(), s0.label(), human(fetched))
	for _, s := range ss {
		for _, arch := range allArches() {
			n, err := fetchIndex(s, arch, base, hashes, byHash, pr)
			fetched += n
			if err != nil {
				return fetched, err
			}
		}
	}
	if err := writeFileAtomic(cached, raw, 0644, true); err != nil {
		return fetched, err
	}
	return fetched, nil
}

func checkDist(rel *Paragraph, dist string) bool {
	suite, code := rel.Get("Suite"), rel.Get("Codename")
	if suite == "" && code == "" {
		return true
	}
	if dist == code || dist == suite {
		return true
	}
	t := dist
	if t == "../project/experimental" {
		t = "experimental"
	}
	if i := strings.LastIndexByte(t, '/'); i >= 0 {
		t = t[:i]
	}
	if t == "." {
		t = ""
	}
	return t == "" || t == code || t == suite
}

const maxIndexDownload = 512 << 20

type capReader struct {
	r    io.Reader
	left int64
	what string
}

func (c *capReader) Read(p []byte) (int, error) {
	if c.left <= 0 {
		var b [1]byte
		n, err := c.r.Read(b[:])
		if n > 0 {
			return 0, fmt.Errorf("size mismatch: %s is larger than expected", c.what)
		}
		return 0, err
	}
	if int64(len(p)) > c.left {
		p = p[:c.left]
	}
	n, err := c.r.Read(p)
	c.left -= int64(n)
	return n, err
}

func stripClearsign(t string) string {
	if i := strings.Index(t, "\n\n"); i >= 0 {
		t = t[i+2:]
	}
	if i := strings.Index(t, "\n-----BEGIN PGP SIGNATURE"); i >= 0 {
		t = t[:i+1]
	}
	return t
}

type hashingReader struct {
	r io.Reader
	h interface {
		io.Writer
		Sum([]byte) []byte
	}
	n int64
}

func (h *hashingReader) Read(p []byte) (int, error) {
	n, err := h.r.Read(p)
	h.h.Write(p[:n])
	h.n += int64(n)
	return n, err
}

func indexEntry(s *Source, arch string, hashes map[string]relEntry) (string, relEntry) {
	exts := []string{".gz", ".xz", ""}
	if cfg.IndexXZ {
		exts = []string{".xz", ".gz", ""}
	}
	for _, ext := range exts {
		cand := s.Comp + "/binary-" + arch + "/Packages" + ext
		if e, ok := hashes[cand]; ok {
			return cand, e
		}
	}
	return "", relEntry{}
}

func indexExpandLimit(hashes map[string]relEntry, s *Source, arch string, compressed int64) int64 {
	if e, ok := hashes[s.Comp+"/binary-"+arch+"/Packages"]; ok && e.size > 0 && e.size < maxIndexSize {
		return e.size
	}
	limit := compressed * 32
	if limit < 1<<20 {
		limit = 1 << 20
	}
	if limit > maxIndexSize {
		limit = maxIndexSize
	}
	return limit
}

func fetchIndex(s *Source, arch, base string, hashes map[string]relEntry, byHash bool, pr *progress) (int64, error) {
	if len(s.Arches) > 0 && !contains(s.Arches, arch) {
		return 0, nil
	}
	name, ent := indexEntry(s, arch, hashes)
	if name == "" {
		if len(hashes) == 0 && s.Trusted {
			name = s.Comp + "/binary-" + arch + "/Packages.gz"
		} else {
			return 0, nil
		}
	}
	url := base + name
	if byHash && ent.hash != "" {
		url = base + filepath.Dir(name) + "/by-hash/SHA256/" + ent.hash
	}
	resp, err := httpGet(url)
	if err != nil && byHash {
		resp, err = httpGet(base + name)
	}
	if err != nil {
		fmt.Printf("Err:%d %s/%s %s Packages\n", pr.next(), s.label(), s.Comp, arch)
		return 0, err
	}
	defer resp.Body.Close()
	limit := int64(maxIndexDownload)
	if ent.size > 0 {
		limit = ent.size
	}
	os.MkdirAll(filepath.Dir(s.indexPath(arch)), 0755)
	tmp, err := os.CreateTemp(filepath.Dir(s.indexPath(arch)), ".dl-")
	if err != nil {
		return 0, err
	}
	defer os.Remove(tmp.Name())
	defer tmp.Close()
	hr := &hashingReader{r: &capReader{r: resp.Body, left: limit, what: url}, h: sha256.New()}
	if _, err := io.Copy(tmp, hr); err != nil {
		return hr.n, fmt.Errorf("%s: %v", url, err)
	}
	if ent.size > 0 && hr.n != ent.size {
		return hr.n, fmt.Errorf("size mismatch for %s (%d != %d)", url, hr.n, ent.size)
	}
	if ent.hash != "" {
		if got := hex.EncodeToString(hr.h.Sum(nil)); got != ent.hash {
			return hr.n, fmt.Errorf("hash sum mismatch for %s", url)
		}
	}
	if _, err := tmp.Seek(0, io.SeekStart); err != nil {
		return hr.n, err
	}
	dr, err := decompressor(name, tmp)
	if err != nil {
		return hr.n, fmt.Errorf("%s: %v", url, err)
	}
	var buf bytes.Buffer
	err = ParseParagraphs(&capReader{r: dr, left: indexExpandLimit(hashes, s, arch, hr.n), what: url + " (uncompressed)"}, indexKeep, func(p *Paragraph) error {
		p.Write822(&buf)
		buf.WriteString("\n")
		return nil
	})
	if err != nil {
		return hr.n, fmt.Errorf("%s: %v", url, err)
	}
	if err := writeKidx(s.indexPath(arch), buf.Bytes()); err != nil {
		return hr.n, err
	}
	fmt.Printf("Get:%d %s/%s %s Packages [%s]\n", pr.next(), s.label(), s.Comp, arch, human(hr.n))
	return hr.n, nil
}

func contains(xs []string, x string) bool {
	for _, y := range xs {
		if y == x {
			return true
		}
	}
	return false
}

func human(n int64) string {
	switch {
	case n >= 1<<30:
		return fmt.Sprintf("%.1f GB", float64(n)/1e9)
	case n >= 1e6:
		return fmt.Sprintf("%.1f MB", float64(n)/1e6)
	case n >= 1e3:
		return fmt.Sprintf("%.0f kB", float64(n)/1e3)
	}
	return fmt.Sprintf("%d B", n)
}

func sortedKeys[M ~map[string]V, V any](m M) []string {
	ks := make([]string, 0, len(m))
	for k := range m {
		ks = append(ks, k)
	}
	sort.Strings(ks)
	return ks
}

func parseRFC1123(s string) (time.Time, bool) {
	f := strings.Fields(s)
	if len(f) != 6 || !strings.HasSuffix(f[0], ",") || len(f[2]) != 3 || len(f[1]) > 2 {
		return time.Time{}, false
	}
	mon := strings.Index("JanFebMarAprMayJunJulAugSepOctNovDec", f[2])
	hms := strings.Split(f[4], ":")
	if mon < 0 || mon%3 != 0 || len(hms) != 3 || len(f[5]) < 3 || strings.Trim(f[5], "ABCDEFGHIJKLMNOPQRSTUVWXYZ") != "" {
		return time.Time{}, false
	}
	var v [5]int
	for i, x := range []string{f[1], f[3], hms[0], hms[1], hms[2]} {
		n, err := strconv.Atoi(x)
		if err != nil || n < 0 || (i > 1 && len(x) != 2) {
			return time.Time{}, false
		}
		v[i] = n
	}
	if v[0] < 1 || v[0] > 31 || v[2] > 23 || v[3] > 59 || v[4] > 59 {
		return time.Time{}, false
	}
	return time.Date(v[1], time.Month(mon/3+1), v[0], v[2], v[3], v[4], 0, time.UTC), true
}
