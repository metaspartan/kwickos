package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"syscall"
	"text/tabwriter"
	"time"
)

type ModelFile struct {
	Name   string `json:"name"`
	Size   int64  `json:"size"`
	SHA256 string `json:"sha256"`
}

type ModelEntry struct {
	ID           string      `json:"id"`
	Title        string      `json:"title"`
	Family       string      `json:"family,omitempty"`
	Class        string      `json:"class,omitempty"`
	Description  string      `json:"description,omitempty"`
	Repo         string      `json:"repo"`
	Commit       string      `json:"commit"`
	Quant        string      `json:"quant"`
	Files        []ModelFile `json:"files"`
	License      string      `json:"license"`
	LicenseURL   string      `json:"license_url,omitempty"`
	CommercialOK bool        `json:"commercial_ok"`
	ParamsB      float64     `json:"params_b,omitempty"`
	ActiveB      float64     `json:"active_params_b,omitempty"`
	Rank         int         `json:"rank,omitempty"`
	CPUOK        bool        `json:"cpu_ok,omitempty"`
	Tags         []string    `json:"tags,omitempty"`
	Shape        *ModelShape `json:"shape,omitempty"`
	Source       string      `json:"source,omitempty"`
}

type ModelCatalog struct {
	Schema  int           `json:"schema"`
	Updated string        `json:"updated"`
	Models  []*ModelEntry `json:"models"`
}

func (m *ModelEntry) size() int64 {
	var n int64
	for _, f := range m.Files {
		n += f.Size
	}
	return n
}

func (m *ModelEntry) moe() bool { return m.Shape != nil && m.Shape.Experts > 0 }

func (m *ModelEntry) fileURL(f ModelFile) string {
	parts := strings.Split(f.Name, "/")
	for i := range parts {
		parts[i] = url.PathEscape(parts[i])
	}
	return "https://huggingface.co/" + m.Repo + "/resolve/" + m.Commit + "/" + strings.Join(parts, "/")
}

func modelCatalogPath() string {
	if p := os.Getenv("KWICK_INFERENCE_MODELS"); p != "" {
		return p
	}
	return filepath.Join(filepath.Dir(catalogPath()), "inference-models.json")
}

func userModelsPath() string { return filepath.Join(inferConfigDir(), "models.json") }

var modelIDRe = regexp.MustCompile(`^[a-z0-9][a-z0-9._-]{0,79}$`)
var sha256Re = regexp.MustCompile(`^[0-9a-f]{64}$`)
var commitRe = regexp.MustCompile(`^[0-9a-f]{40}$`)
var repoRe = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,95}/[A-Za-z0-9][A-Za-z0-9._-]{0,95}$`)

func validModelFile(n string) bool {
	if n == "" || strings.HasPrefix(n, "/") || strings.Contains(n, "\\") || !strings.HasSuffix(n, ".gguf") {
		return false
	}
	for _, p := range strings.Split(n, "/") {
		if p == "" || p == "." || p == ".." {
			return false
		}
	}
	return true
}

func (m *ModelEntry) validate() error {
	if !modelIDRe.MatchString(m.ID) {
		return fmt.Errorf("invalid model id %q", m.ID)
	}
	if !repoRe.MatchString(m.Repo) {
		return fmt.Errorf("%s: invalid repository %q", m.ID, m.Repo)
	}
	if !commitRe.MatchString(m.Commit) {
		return fmt.Errorf("%s: the commit is not pinned", m.ID)
	}
	if len(m.Files) == 0 {
		return fmt.Errorf("%s: no files", m.ID)
	}
	for _, f := range m.Files {
		if !validModelFile(f.Name) || !sha256Re.MatchString(f.SHA256) || f.Size <= 0 {
			return fmt.Errorf("%s: file %q is not pinned by size and sha256", m.ID, f.Name)
		}
	}
	return nil
}

func parseModelCatalog(b []byte) (*ModelCatalog, error) {
	var c ModelCatalog
	if err := json.Unmarshal(b, &c); err != nil {
		return nil, err
	}
	seen := map[string]bool{}
	for _, m := range c.Models {
		if err := m.validate(); err != nil {
			return nil, err
		}
		if seen[m.ID] {
			return nil, fmt.Errorf("model %s is listed twice", m.ID)
		}
		seen[m.ID] = true
		if m.Source == "" {
			m.Source = "catalog"
		}
	}
	return &c, nil
}

func loadModelCatalog() (*ModelCatalog, error) {
	b, err := os.ReadFile(modelCatalogPath())
	if err != nil {
		return nil, fmt.Errorf("cannot read the model catalog: %v", err)
	}
	c, err := parseModelCatalog(b)
	if err != nil {
		return nil, fmt.Errorf("model catalog %s: %v", modelCatalogPath(), err)
	}
	if ub, err := os.ReadFile(userModelsPath()); err == nil {
		if uc, err := parseModelCatalog(ub); err == nil {
			for _, m := range uc.Models {
				if _, err := c.find(m.ID); err == nil {
					continue
				}
				m.Source = "hf"
				c.Models = append(c.Models, m)
			}
		} else {
			warnf("ignoring %s: %v", shortPath(userModelsPath()), err)
		}
	}
	return c, nil
}

func (c *ModelCatalog) find(id string) (*ModelEntry, error) {
	id = strings.ToLower(strings.TrimSpace(id))
	for _, m := range c.Models {
		if m.ID == id {
			return m, nil
		}
	}
	return nil, fmt.Errorf("unknown model %q (see: kwick-agents inference models)", id)
}

func modelDir(id string) string { return filepath.Join(inferModelsDir(), id) }

type modelManifest struct {
	ModelEntry
	Verified    bool   `json:"verified"`
	VerifiedAt  string `json:"verified_at,omitempty"`
	InstalledAt string `json:"installed_at"`
}

func readManifest(id string) (*modelManifest, bool) {
	var m modelManifest
	if readJSONFile(filepath.Join(modelDir(id), "manifest.json"), &m) != nil || m.ID != id {
		return nil, false
	}
	return &m, true
}

func installedModel(m *ModelEntry) (installed, verified bool) {
	man, ok := readManifest(m.ID)
	if !ok {
		return false, false
	}
	for _, f := range m.Files {
		st, err := os.Stat(filepath.Join(modelDir(m.ID), filepath.FromSlash(f.Name)))
		if err != nil || st.Size() != f.Size {
			return false, false
		}
	}
	same := len(man.Files) == len(m.Files)
	for i := range m.Files {
		if same && (man.Files[i].SHA256 != m.Files[i].SHA256 || man.Files[i].Name != m.Files[i].Name) {
			same = false
		}
	}
	return true, man.Verified && same
}

func modelPath(m *ModelEntry) string {
	return filepath.Join(modelDir(m.ID), filepath.FromSlash(m.Files[0].Name))
}

func freeBytes(dir string) int64 {
	for d := dir; ; d = filepath.Dir(d) {
		var st syscall.Statfs_t
		if err := syscall.Statfs(d, &st); err == nil {
			return int64(st.Bavail) * int64(st.Bsize)
		}
		if d == "/" || d == "." {
			return -1
		}
	}
}

func hashFile(p string, h io.Writer) (int64, error) {
	f, err := os.Open(p)
	if err != nil {
		return 0, err
	}
	defer f.Close()
	return io.Copy(h, f)
}

func fileSHA256(p string) (string, error) {
	h := sha256.New()
	if _, err := hashFile(p, h); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

var modelHTTP = &http.Client{Timeout: 0, Transport: &http.Transport{Proxy: http.ProxyFromEnvironment, TLSHandshakeTimeout: 30 * time.Second, ResponseHeaderTimeout: 90 * time.Second}}

func resumeDownload(u string, want string, size int64, dest string) error {
	want = strings.ToLower(want)
	if !sha256Re.MatchString(want) {
		return fmt.Errorf("refusing to download %s without a pinned sha256", u)
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	part := dest + ".part"
	var lastErr error
	for attempt := 0; attempt < 6; attempt++ {
		if attempt > 0 {
			time.Sleep(time.Duration(attempt*attempt) * time.Second)
		}
		var off int64
		if st, err := os.Stat(part); err == nil {
			off = st.Size()
		}
		if size > 0 && off > size {
			os.Remove(part)
			off = 0
		}
		if size > 0 && off == size {
			break
		}
		lastErr = downloadRange(u, part, off, size)
		if lastErr == nil {
			break
		}
		var fatal fatalDownload
		if errors.As(lastErr, &fatal) {
			return lastErr
		}
		warnf("%v; retrying", lastErr)
	}
	if lastErr != nil {
		return lastErr
	}
	say("Checking sha256 of %s", path.Base(dest))
	got, err := fileSHA256(part)
	if err != nil {
		return err
	}
	if got != want {
		os.Remove(part)
		return hashMismatch{u, got, want}
	}
	return os.Rename(part, dest)
}

type fatalDownload struct{ msg string }

func (f fatalDownload) Error() string { return f.msg }

func downloadRange(u, part string, off, size int64) error {
	req, err := http.NewRequest("GET", u, nil)
	if err != nil {
		return fatalDownload{err.Error()}
	}
	req.Header.Set("User-Agent", "kwick-agents/"+version)
	if off > 0 {
		req.Header.Set("Range", fmt.Sprintf("bytes=%d-", off))
	}
	resp, err := modelHTTP.Do(req)
	if err != nil {
		return fmt.Errorf("download failed: %v", err)
	}
	defer resp.Body.Close()
	flags := os.O_CREATE | os.O_WRONLY
	switch resp.StatusCode {
	case 206:
		flags |= os.O_APPEND
	case 200:
		flags |= os.O_TRUNC
		off = 0
	case 416:
		return nil
	case 401, 403, 404:
		return fatalDownload{fmt.Sprintf("%s returned %s", u, resp.Status)}
	default:
		return fmt.Errorf("%s returned %s", u, resp.Status)
	}
	f, err := os.OpenFile(part, flags, 0o644)
	if err != nil {
		return fatalDownload{err.Error()}
	}
	total := size
	if total <= 0 && resp.ContentLength > 0 {
		total = off + resp.ContentLength
	}
	p := &progress{total: total, done: off, label: path.Base(part[:len(part)-5]), tty: isTerminal(2)}
	_, err = io.Copy(io.MultiWriter(f, p), resp.Body)
	if p.tty {
		fmt.Fprint(os.Stderr, "\r\033[K")
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		return fmt.Errorf("download interrupted at %s: %v", humanBytes(p.done), err)
	}
	if size > 0 && p.done < size {
		return fmt.Errorf("download ended early at %s of %s", humanBytes(p.done), humanBytes(size))
	}
	return nil
}

func pullModel(m *ModelEntry) error {
	if err := m.validate(); err != nil {
		return err
	}
	dir := modelDir(m.ID)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	unlock, err := lockFile(filepath.Join(dir, ".lock"))
	if err != nil {
		return err
	}
	defer unlock()
	var need int64
	for _, f := range m.Files {
		d := filepath.Join(dir, filepath.FromSlash(f.Name))
		if st, err := os.Stat(d); err == nil && st.Size() == f.Size {
			continue
		}
		need += f.Size
		if st, err := os.Stat(d + ".part"); err == nil && st.Size() <= f.Size {
			need -= st.Size()
		}
	}
	if free := freeBytes(dir); free >= 0 && need > 0 && free < need+(1<<30) {
		return fmt.Errorf("%s needs %s of free space in %s; %s is free", m.ID, humanBytes(need), shortPath(dir), humanBytes(free))
	}
	say("== %s (%s, %s, licence %s)", m.ID, m.Quant, humanBytes(m.size()), m.License)
	for _, f := range m.Files {
		d := filepath.Join(dir, filepath.FromSlash(f.Name))
		if st, err := os.Stat(d); err == nil && st.Size() == f.Size {
			if man, ok := readManifest(m.ID); ok && man.Verified {
				continue
			}
			got, err := fileSHA256(d)
			if err == nil && got == f.SHA256 {
				continue
			}
			os.Remove(d)
		}
		u := m.fileURL(f)
		say("Downloading %s", u)
		say("Expected sha256 %s", f.SHA256)
		if err := resumeDownload(u, f.SHA256, f.Size, d); err != nil {
			return err
		}
		say("sha256 verified")
	}
	man := modelManifest{ModelEntry: *m, Verified: true, VerifiedAt: nowStamp(), InstalledAt: nowStamp()}
	if old, ok := readManifest(m.ID); ok && old.InstalledAt != "" {
		man.InstalledAt = old.InstalledAt
	}
	if man.Shape == nil {
		if sh, err := localShape(m); err == nil {
			man.Shape = &sh
		}
	}
	return writeJSONFile(filepath.Join(dir, "manifest.json"), man, 0o644)
}

func verifyModel(m *ModelEntry) error {
	dir := modelDir(m.ID)
	for _, f := range m.Files {
		d := filepath.Join(dir, filepath.FromSlash(f.Name))
		st, err := os.Stat(d)
		if err != nil {
			return fmt.Errorf("%s: %s is missing", m.ID, f.Name)
		}
		if st.Size() != f.Size {
			return fmt.Errorf("%s: %s has %d bytes, want %d", m.ID, f.Name, st.Size(), f.Size)
		}
		got, err := fileSHA256(d)
		if err != nil {
			return err
		}
		if got != f.SHA256 {
			man, _ := readManifest(m.ID)
			if man != nil {
				man.Verified = false
				writeJSONFile(filepath.Join(dir, "manifest.json"), man, 0o644)
			}
			return fmt.Errorf("%s: sha256 of %s is %s, want %s", m.ID, f.Name, got, f.SHA256)
		}
	}
	man, ok := readManifest(m.ID)
	if !ok {
		man = &modelManifest{ModelEntry: *m, InstalledAt: nowStamp()}
	}
	man.Verified = true
	man.VerifiedAt = nowStamp()
	return writeJSONFile(filepath.Join(dir, "manifest.json"), man, 0o644)
}

func lockFile(p string) (func(), error) {
	f, err := os.OpenFile(p, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		f.Close()
		return nil, fmt.Errorf("another download of this model is running")
	}
	return func() {
		syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		f.Close()
	}, nil
}

func localShape(m *ModelEntry) (ModelShape, error) {
	var gs []*ggufFile
	var sizes []int64
	for _, f := range m.Files {
		g, sz, err := localGGUF(filepath.Join(modelDir(m.ID), filepath.FromSlash(f.Name)))
		if err != nil {
			return ModelShape{}, err
		}
		gs = append(gs, g)
		sizes = append(sizes, sz)
	}
	return shapeFromGGUF(gs, sizes)
}

func shapeCachePath(m *ModelEntry) string {
	return filepath.Join(userScope().State, "gguf", m.Files[0].SHA256+".json")
}

func modelShape(m *ModelEntry) (ModelShape, error) {
	if m.Shape != nil {
		return *m.Shape, nil
	}
	if man, ok := readManifest(m.ID); ok && man.Shape != nil {
		return *man.Shape, nil
	}
	var sh ModelShape
	if readJSONFile(shapeCachePath(m), &sh) == nil && sh.Arch != "" {
		return sh, nil
	}
	if inst, _ := installedModel(m); inst {
		if s, err := localShape(m); err == nil {
			return s, nil
		}
	}
	var gs []*ggufFile
	var sizes []int64
	for _, f := range m.Files {
		g, sz, err := remoteGGUF(m.fileURL(f))
		if err != nil {
			return ModelShape{}, fmt.Errorf("reading the GGUF header of %s: %v", f.Name, err)
		}
		if sz == 0 {
			sz = f.Size
		}
		gs = append(gs, g)
		sizes = append(sizes, sz)
	}
	sh, err := shapeFromGGUF(gs, sizes)
	if err != nil {
		return sh, err
	}
	writeJSONFile(shapeCachePath(m), sh, 0o644)
	return sh, nil
}

type ModelItem struct {
	ModelEntry
	Size        int64  `json:"size"`
	MoE         bool   `json:"moe"`
	ContextMax  int64  `json:"context_max"`
	Installed   bool   `json:"installed"`
	Verified    bool   `json:"verified"`
	Current     bool   `json:"current"`
	Recommended bool   `json:"recommended"`
	Fit         *Fit   `json:"fit"`
	FitError    string `json:"fit_error,omitempty"`
}

func modelItems(mc *ModelCatalog, hw Hardware, ctx int64, cfg *inferConfig, remote bool) []ModelItem {
	var items []ModelItem
	for _, m := range mc.Models {
		it := ModelItem{ModelEntry: *m, Size: m.size(), MoE: m.moe()}
		it.Shape = nil
		it.Installed, it.Verified = installedModel(m)
		it.Current = cfg.Model == m.ID
		var sh ModelShape
		var err error
		if m.Shape != nil || remote || it.Installed {
			sh, err = modelShape(m)
		} else {
			err = fmt.Errorf("no shape in the catalog")
		}
		if err == nil {
			f := computeFit(sh, hw, ctx)
			it.Fit = &f
			it.ContextMax = sh.ContextMax
			it.MoE = sh.Experts > 0
		} else {
			it.FitError = err.Error()
		}
		items = append(items, it)
	}
	if best := bestModel(items, hw); best != "" {
		for i := range items {
			items[i].Recommended = items[i].ID == best
		}
	}
	if items == nil {
		items = []ModelItem{}
	}
	return items
}

func fitScore(v string) int {
	switch v {
	case "gpu", "cpu":
		return 3
	case "moe-offload":
		return 2
	case "cpu-split":
		return 1
	}
	return 0
}

func bestModel(items []ModelItem, hw Hardware) string {
	best := -1
	for i, it := range items {
		if it.Fit == nil || it.Source != "catalog" {
			continue
		}
		s := fitScore(it.Fit.Verdict)
		if s < 2 {
			continue
		}
		if hw.Accelerator == "cpu" && !it.CPUOK {
			continue
		}
		if best < 0 {
			best = i
			continue
		}
		b := items[best]
		bs := fitScore(b.Fit.Verdict)
		if s > bs || (s == bs && it.Rank > b.Rank) {
			best = i
		}
	}
	if best < 0 {
		return ""
	}
	return items[best].ID
}

func cmdInferModels(o iopts) error {
	mc, err := loadModelCatalog()
	if err != nil {
		return err
	}
	hw := detectHardware()
	cfg := loadInferConfig()
	items := modelItems(mc, hw, int64(o.ctx), cfg, o.remote)
	var out []ModelItem
	for _, it := range items {
		if o.installed && !it.Installed {
			continue
		}
		if o.fits && (it.Fit == nil || it.Fit.Verdict == "no") {
			continue
		}
		out = append(out, it)
	}
	if out == nil {
		out = []ModelItem{}
	}
	if o.json {
		emitJSON(map[string]any{"schema": 1, "current": cfg.Model, "models_dir": inferModelsDir(),
			"budget": map[string]any{"memory_budget_mb": hw.MemoryBudgetMB, "ram_budget_mb": hw.RAMBudgetMB, "vram_mb": hw.VRAMMB, "unified": hw.Unified, "accelerator": hw.Accelerator},
			"models": out})
		return nil
	}
	tw := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "ID\tSIZE\tFIT\tSTATE\tLICENCE\tNOTE")
	for _, it := range out {
		st := "-"
		if it.Installed {
			st = "installed"
			if !it.Verified {
				st = "unverified"
			}
		}
		if it.Current {
			st += ",current"
		}
		v, note := "?", it.FitError
		if it.Fit != nil {
			v, note = it.Fit.Verdict, it.Fit.Reason
		}
		if it.Recommended {
			note = "best for this machine; " + note
		}
		lic := it.License
		if !it.CommercialOK {
			lic += " (non-commercial?)"
		}
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\t%s\t%s\n", it.ID, humanBytes(it.Size), v, st, lic, note)
	}
	return tw.Flush()
}

func cmdInferModel(o iopts, pos []string) error {
	if len(pos) == 0 {
		return fmt.Errorf("usage: kwick-agents inference model pull ID | add hf://REPO[:QUANT] | rm ID | verify [ID]")
	}
	sub, args := pos[0], pos[1:]
	mc, err := loadModelCatalog()
	if err != nil {
		return err
	}
	switch sub {
	case "pull", "download":
		if len(args) == 0 {
			return fmt.Errorf("usage: kwick-agents inference model pull ID...")
		}
		for _, id := range args {
			var m *ModelEntry
			if strings.HasPrefix(id, "hf://") {
				m, err = addHFModel(id)
			} else {
				m, err = mc.find(id)
			}
			if err != nil {
				return err
			}
			if err := pullModel(m); err != nil {
				return err
			}
			say("%s installed in %s", m.ID, shortPath(modelDir(m.ID)))
			if !m.CommercialOK {
				say("Note: the licence of %s (%s) may not allow commercial use: %s", m.ID, m.License, m.LicenseURL)
			}
		}
		return nil
	case "add":
		if len(args) != 1 {
			return fmt.Errorf("usage: kwick-agents inference model add hf://REPO[:QUANT]")
		}
		m, err := addHFModel(args[0])
		if err != nil {
			return err
		}
		if o.json {
			emitJSON(map[string]any{"schema": 1, "model": m})
		} else {
			say("added %s (%s, %s, licence %s); download it with: kwick-agents inference model pull %s", m.ID, m.Quant, humanBytes(m.size()), m.License, m.ID)
		}
		return nil
	case "rm", "remove":
		if len(args) == 0 {
			return fmt.Errorf("usage: kwick-agents inference model rm ID...")
		}
		cfg := loadInferConfig()
		for _, id := range args {
			id = strings.ToLower(id)
			if !modelIDRe.MatchString(id) {
				return fmt.Errorf("invalid model id %q", id)
			}
			d := modelDir(id)
			if !exists(d) {
				warnf("%s is not installed", id)
				continue
			}
			if err := os.RemoveAll(d); err != nil {
				return err
			}
			if cfg.Model == id {
				cfg.Model = ""
				saveInferConfig(cfg)
			}
			say("%s removed", id)
		}
		if serviceRunning() {
			writePreset(loadInferConfig())
		}
		return nil
	case "verify":
		ids := args
		if len(ids) == 0 {
			for _, m := range mc.Models {
				if inst, _ := installedModel(m); inst || exists(modelDir(m.ID)) {
					ids = append(ids, m.ID)
				}
			}
		}
		failed := false
		for _, id := range ids {
			m, err := mc.find(id)
			if err != nil {
				return err
			}
			if err := verifyModel(m); err != nil {
				warnf("%v", err)
				failed = true
				continue
			}
			say("%s: sha256 of every file verified", m.ID)
		}
		if failed {
			return exitErr{1}
		}
		return nil
	case "shape":
		if len(args) != 1 {
			return fmt.Errorf("usage: kwick-agents inference model shape ID")
		}
		m, err := mc.find(args[0])
		if err != nil {
			return err
		}
		m.Shape = nil
		sh, err := modelShape(m)
		if err != nil {
			return err
		}
		emitJSON(sh)
		return nil
	case "header":
		if len(args) != 1 {
			return fmt.Errorf("usage: kwick-agents inference model header ID")
		}
		m, err := mc.find(args[0])
		if err != nil {
			return err
		}
		g, size, err := remoteGGUF(m.fileURL(m.Files[0]))
		if err != nil {
			return err
		}
		emitJSON(map[string]any{"version": g.Version, "size": size, "tensors": len(g.Tensors), "data_offset": g.DataOffset, "kv": g.KV})
		return nil
	}
	return fmt.Errorf("usage: kwick-agents inference model pull|add|rm|verify")
}

type hfSibling struct {
	Name string `json:"rfilename"`
	Size int64  `json:"size"`
	LFS  *struct {
		SHA256 string `json:"sha256"`
		Size   int64  `json:"size"`
	} `json:"lfs"`
}

type hfModel struct {
	ID       string      `json:"id"`
	SHA      string      `json:"sha"`
	Gated    any         `json:"gated"`
	Siblings []hfSibling `json:"siblings"`
	CardData struct {
		License     string `json:"license"`
		LicenseName string `json:"license_name"`
		LicenseLink string `json:"license_link"`
	} `json:"cardData"`
}

var hfAPIBase = "https://huggingface.co"

var permissive = map[string]bool{"apache-2.0": true, "mit": true, "bsd-3-clause": true, "bsd-2-clause": true, "openrail": false}

var quantPrefs = []string{"Q4_K_M", "Q4_K_S", "MXFP4", "Q4_0", "IQ4_XS", "Q4_1", "Q5_K_M", "Q8_0"}

func hfPickFiles(sibs []hfSibling, quant string) (string, []ModelFile, error) {
	var ggufs []hfSibling
	for _, s := range sibs {
		low := strings.ToLower(path.Base(s.Name))
		if !strings.HasSuffix(low, ".gguf") || strings.HasPrefix(low, "mmproj") || strings.HasPrefix(low, "mtp-") || strings.Contains(low, "imatrix") || s.LFS == nil {
			continue
		}
		ggufs = append(ggufs, s)
	}
	match := func(q string) []hfSibling {
		var out []hfSibling
		ql := strings.ToLower(q)
		re := regexp.MustCompile(`(^|[-_.])` + regexp.QuoteMeta(ql) + `([-_.]|$)`)
		for _, s := range ggufs {
			b := strings.ToLower(path.Base(s.Name))
			if re.MatchString(strings.TrimSuffix(b, ".gguf")) {
				out = append(out, s)
			}
		}
		return out
	}
	var got []hfSibling
	q := quant
	if q != "" {
		got = match(q)
	} else {
		for _, p := range quantPrefs {
			if got = match(p); len(got) > 0 {
				q = p
				break
			}
		}
	}
	if len(got) == 0 {
		var names []string
		for _, s := range ggufs {
			names = append(names, s.Name)
		}
		return "", nil, fmt.Errorf("no GGUF file for quantisation %q (files: %s)", quant, strings.Join(names, ", "))
	}
	sort.Slice(got, func(i, j int) bool { return got[i].Name < got[j].Name })
	shard := regexp.MustCompile(`-(\d{5})-of-(\d{5})\.gguf$`)
	if len(got) > 1 {
		dirs := map[string]bool{}
		for _, s := range got {
			dirs[path.Dir(s.Name)+"|"+shard.ReplaceAllString(s.Name, "")] = true
		}
		if len(dirs) > 1 {
			var names []string
			for _, s := range got {
				names = append(names, s.Name)
			}
			return "", nil, fmt.Errorf("quantisation %q matches several files (%s); name one exactly", q, strings.Join(names, ", "))
		}
	}
	var files []ModelFile
	for _, s := range got {
		files = append(files, ModelFile{Name: s.Name, Size: s.LFS.Size, SHA256: strings.ToLower(s.LFS.SHA256)})
	}
	return strings.ToUpper(q), files, nil
}

func addHFModel(ref string) (*ModelEntry, error) {
	rest := strings.TrimPrefix(ref, "hf://")
	repo, quant := rest, ""
	if i := strings.LastIndex(rest, ":"); i > 0 {
		repo, quant = rest[:i], rest[i+1:]
	}
	if !repoRe.MatchString(repo) {
		return nil, fmt.Errorf("usage: hf://OWNER/REPO[:QUANT], for example hf://unsloth/Qwen3.5-4B-GGUF:Q4_K_M")
	}
	body, err := fetchText(hfAPIBase+"/api/models/"+repo+"?blobs=true", 32<<20)
	if err != nil {
		return nil, fmt.Errorf("Hugging Face: %v", err)
	}
	var hm hfModel
	if err := json.Unmarshal([]byte(body), &hm); err != nil {
		return nil, fmt.Errorf("Hugging Face returned an unexpected answer: %v", err)
	}
	if g, ok := hm.Gated.(bool); (ok && g) || (!ok && hm.Gated != nil) {
		return nil, fmt.Errorf("%s is gated on Hugging Face (accept its terms there; gated downloads are not supported)", repo)
	}
	if !commitRe.MatchString(hm.SHA) {
		return nil, fmt.Errorf("%s: no commit in the API answer", repo)
	}
	q, files, err := hfPickFiles(hm.Siblings, quant)
	if err != nil {
		return nil, fmt.Errorf("%s: %v", repo, err)
	}
	lic := hm.CardData.License
	if lic == "other" && hm.CardData.LicenseName != "" {
		lic = hm.CardData.LicenseName
	}
	if lic == "" {
		lic = "unknown"
	}
	licURL := hm.CardData.LicenseLink
	if licURL == "" || !strings.HasPrefix(licURL, "http") {
		licURL = "https://huggingface.co/" + repo
	}
	base := strings.ToLower(path.Base(repo))
	base = strings.TrimSuffix(strings.TrimSuffix(base, "-gguf"), "_gguf")
	id := regexp.MustCompile(`[^a-z0-9._-]+`).ReplaceAllString(base+"-"+strings.ToLower(q), "-")
	if len(id) > 80 {
		id = id[:80]
	}
	m := &ModelEntry{ID: id, Title: path.Base(repo) + " " + q, Repo: repo, Commit: hm.SHA, Quant: q, Files: files,
		License: lic, LicenseURL: licURL, CommercialOK: permissive[lic], Source: "hf"}
	if err := m.validate(); err != nil {
		return nil, err
	}
	var uc ModelCatalog
	readJSONFile(userModelsPath(), &uc)
	uc.Schema = 1
	uc.Updated = time.Now().UTC().Format("2006-01-02")
	var kept []*ModelEntry
	for _, x := range uc.Models {
		if x.ID != m.ID {
			kept = append(kept, x)
		}
	}
	uc.Models = append(kept, m)
	if err := writeJSONFile(userModelsPath(), uc, 0o644); err != nil {
		return nil, err
	}
	return m, nil
}
