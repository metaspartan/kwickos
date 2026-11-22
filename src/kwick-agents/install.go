package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

func say(f string, a ...any) { fmt.Fprintf(os.Stderr, f+"\n", a...) }

func pkgDir(sc Scope, e *Entry) string {
	if e.Kind == "runtime" {
		return filepath.Join(sc.Data, "runtimes", e.Name, e.Version)
	}
	return filepath.Join(sc.Data, "pkgs", e.Name, e.Version)
}

func runtimeFor(c *Catalog, e *Entry, prefer Scope) (*Installed, error) {
	if e.Runtime == "" {
		return nil, nil
	}
	scopes := []Scope{systemScope()}
	if !prefer.System {
		scopes = append([]Scope{userScope()}, scopes...)
	}
	for _, sc := range scopes {
		if in, ok := loadState(sc).Agents[e.Runtime]; ok && exists(in.Dir) {
			return in, nil
		}
	}
	return nil, fmt.Errorf("runtime %s is not installed (kwick-agents install %s)", e.Runtime, e.Runtime)
}

func ensureRuntime(c *Catalog, sc Scope, e *Entry, o opts) (*Installed, error) {
	if e.Runtime == "" {
		return nil, nil
	}
	rt := c.byName[e.Runtime]
	cands := []Scope{systemScope()}
	if !sc.System {
		cands = []Scope{userScope(), systemScope()}
	}
	for _, s := range cands {
		if in, ok := loadState(s).Agents[rt.Name]; ok && in.Version == rt.Version && exists(in.Dir) {
			return in, nil
		}
	}
	say("== %s %s (runtime for %s)", rt.Name, rt.Version, e.Name)
	st := loadState(sc)
	if err := installEntry(c, sc, st, rt, o); err != nil {
		return nil, err
	}
	return loadState(sc).Agents[rt.Name], nil
}

func installEntry(c *Catalog, sc Scope, st *State, e *Entry, o opts) error {
	arch := hostArch()
	if ok, why := c.supported(e, arch); !ok {
		return fmt.Errorf("%s is not available here: %s", e.Name, why)
	}
	if e.Method == "placeholder" {
		return fmt.Errorf("%s: %s", e.Name, e.Notes)
	}
	for _, n := range e.Needs {
		if lookPath(n) == "" {
			return fmt.Errorf("%s needs '%s' (sudo apt install %s)", e.Name, n, n)
		}
	}
	ver := e.Version
	asset, hasAsset := e.asset(arch)
	if o.latest && e.Name == "cybara" {
		a, v, err := cybaraLatest(arch)
		if err != nil {
			return err
		}
		asset, ver, hasAsset = a, v, true
		say("Latest Cybara release %s; its checksum comes from the vendor's .sha256 file, not from KwickOS.", v)
	}
	if cur, ok := st.Agents[e.Name]; ok && cur.Version == ver && exists(cur.Dir) && !cur.Legacy {
		say("%s %s is already installed (%s)", e.Name, ver, shortPath(cur.Dir))
		if e.Kind != "runtime" {
			cur.Shims = writeShims(sc, e, cur.Shims)
			saveState(sc, st)
		}
		return nil
	}
	rt, err := ensureRuntime(c, sc, e, o)
	if err != nil {
		return err
	}
	dir := filepath.Join(filepath.Dir(pkgDir(sc, e)), ver)
	os.RemoveAll(dir)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	ok := false
	defer func() {
		if !ok {
			os.RemoveAll(dir)
		}
	}()
	dl := filepath.Join(sc.Data, "downloads")
	switch e.Method {
	case "binary", "archive", "node-bundle":
		if !hasAsset {
			return fmt.Errorf("no download for %s on %s", e.Name, arch)
		}
		say("Downloading %s", asset.URL)
		say("Expected sha256 %s", asset.SHA256)
		file := filepath.Join(dl, asset.SHA256)
		if err := download(asset.URL, asset.SHA256, asset.Size, file); err != nil {
			return err
		}
		say("sha256 verified")
		if e.Method == "binary" {
			dst := filepath.Join(dir, e.Bin[e.mainCmd()])
			os.MkdirAll(filepath.Dir(dst), 0o755)
			if err := os.Rename(file, dst); err != nil {
				if err := copyFile(file, dst); err != nil {
					return err
				}
				os.Remove(file)
			}
			os.Chmod(dst, 0o755)
		} else {
			if err := extract(file, asset.Format, dir, asset.Strip, asset.Rename); err != nil {
				return err
			}
			os.Remove(file)
		}
	case "npm-lock":
		if err := installNpm(sc, e, rt, dir); err != nil {
			return err
		}
	case "uv-lock":
		if err := installUvLock(sc, e, rt, dir); err != nil {
			return err
		}
	case "git-uv":
		if err := installGitUv(sc, e, rt, dir); err != nil {
			return err
		}
	default:
		return fmt.Errorf("unknown install method %q", e.Method)
	}
	for cmd, rel := range e.Bin {
		p := filepath.Join(dir, rel)
		if !exists(p) {
			return fmt.Errorf("%s: %s is missing after the install (%s)", e.Name, cmd, rel)
		}
		if e.Method != "node-bundle" && e.Method != "npm-lock" {
			os.Chmod(p, 0o755)
		}
	}
	st = loadState(sc)
	old := st.Agents[e.Name]
	in := &Installed{Name: e.Name, Version: ver, Method: e.Method, Dir: dir, Runtime: e.Runtime, Commands: e.commands(), InstalledAt: nowStamp(), Scope: sc.Name()}
	if old != nil && old.Legacy {
		os.Remove(filepath.Join(sysBin, "cybara"))
		os.Remove(filepath.Join(sysState, "cybara"))
		old = nil
	}
	var prevShims []string
	if old != nil {
		prevShims = old.Shims
	}
	if e.Kind != "runtime" {
		in.Shims = writeShims(sc, e, prevShims)
	}
	st.Agents[e.Name] = in
	if err := saveState(sc, st); err != nil {
		return err
	}
	ok = true
	if old != nil && old.Dir != dir && strings.HasPrefix(old.Dir, sc.Data+"/") {
		os.RemoveAll(old.Dir)
	}
	say("%s %s installed in %s", e.Name, ver, shortPath(dir))
	return nil
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o755)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

func shimText(e *Entry, cmd string) string {
	return fmt.Sprintf("#!/bin/sh\nexec %s run --cmd %s %s -- \"$@\"\n", selfPath, cmd, e.Name)
}

func isOurShim(p string) bool {
	b, err := os.ReadFile(p)
	if err != nil || len(b) > 512 {
		return false
	}
	return bytes.Contains(b, []byte("exec "+selfPath+" run --cmd "))
}

func writeShims(sc Scope, e *Entry, prev []string) []string {
	var out []string
	keep := map[string]bool{}
	for _, cmd := range e.commands() {
		p := filepath.Join(sc.Bin, cmd)
		if exists(p) && !isOurShim(p) {
			warnf("%s exists and was not made by kwick-agents; start this agent with: kwick-agents run %s", shortPath(p), e.Name)
			continue
		}
		os.MkdirAll(sc.Bin, 0o755)
		if err := writeFileAtomic(p, []byte(shimText(e, cmd)), 0o755); err != nil {
			warnf("cannot write %s: %v", p, err)
			continue
		}
		out = append(out, p)
		keep[p] = true
	}
	for _, p := range prev {
		if !keep[p] && isOurShim(p) {
			os.Remove(p)
		}
	}
	if !sc.System {
		path := os.Getenv("PATH")
		if len(out) > 0 && !strings.Contains(":"+path+":", ":"+sc.Bin+":") {
			say("Note: %s is not on your PATH yet; it is added at your next login (/etc/profile.d/30-kwick-agents.sh).", shortPath(sc.Bin))
		}
	}
	return out
}

func runtimeBin(rt *Installed, name string) string {
	switch name {
	case "node":
		return filepath.Join(rt.Dir, "bin", "node")
	case "npm":
		return filepath.Join(rt.Dir, "lib", "node_modules", "npm", "bin", "npm-cli.js")
	case "uv":
		return filepath.Join(rt.Dir, "uv")
	case "bun":
		return filepath.Join(rt.Dir, "bun")
	}
	return ""
}

func helperEnv(sc Scope, extra ...string) []string {
	env := []string{
		"HOME=" + homeDir(),
		"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
		"LANG=C.UTF-8",
		"TMPDIR=/tmp",
	}
	for _, k := range []string{"http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY", "no_proxy", "NO_PROXY", "SSL_CERT_FILE", "TERM"} {
		if v := os.Getenv(k); v != "" {
			env = append(env, k+"="+v)
		}
	}
	return append(env, extra...)
}

func confined(writable []string, network bool, argv []string, env []string, dir string) *exec.Cmd {
	bw := lookPath("bwrap")
	if bw == "" {
		c := exec.Command(argv[0], argv[1:]...)
		c.Env, c.Dir = env, dir
		return c
	}
	a := []string{"--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc", "--tmpfs", "/tmp", "--die-with-parent", "--new-session", "--unshare-all"}
	if network {
		a = append(a, "--share-net")
	}
	for _, w := range writable {
		os.MkdirAll(w, 0o755)
		a = append(a, "--bind", w, w)
	}
	if dir != "" {
		a = append(a, "--chdir", dir)
	}
	a = append(a, "--")
	a = append(a, argv...)
	c := exec.Command(bw, a...)
	c.Env = env
	return c
}

func runStep(label string, c *exec.Cmd) error {
	c.Stdout = os.Stderr
	c.Stderr = os.Stderr
	say("-> %s", label)
	if err := c.Run(); err != nil {
		return fmt.Errorf("%s failed: %v", label, err)
	}
	return nil
}

func installNpm(sc Scope, e *Entry, rt *Installed, dir string) error {
	src := filepath.Join(locksDir(), e.Lock)
	for _, f := range []string{"package.json", "package-lock.json"} {
		if err := copyFile(filepath.Join(src, f), filepath.Join(dir, f)); err != nil {
			return fmt.Errorf("lock file %s: %v", f, err)
		}
		os.Chmod(filepath.Join(dir, f), 0o644)
	}
	node := runtimeBin(rt, "node")
	npm := runtimeBin(rt, "npm")
	cache := filepath.Join(sc.Data, "cache", "npm")
	env := helperEnv(sc, "npm_config_cache="+cache, "npm_config_update_notifier=false", "npm_config_fund=false", "npm_config_audit=false",
		"PATH="+filepath.Join(rt.Dir, "bin")+":/usr/local/bin:/usr/bin:/bin")
	say("npm ci verifies the sha512 of every package against %s", filepath.Join(src, "package-lock.json"))
	c := confined([]string{dir, cache}, true, []string{node, npm, "ci", "--ignore-scripts", "--no-audit", "--no-fund", "--omit=dev"}, env, dir)
	if err := runStep("npm ci --ignore-scripts", c); err != nil {
		return err
	}
	for _, p := range e.Scripts {
		c := confined([]string{dir}, false, []string{node, npm, "rebuild", "--foreground-scripts", "--allow-scripts=" + p, p}, env, dir)
		if err := runStep("install scripts of "+p+" (sandboxed, no network)", c); err != nil {
			c2 := confined([]string{dir}, false, []string{node, npm, "rebuild", "--foreground-scripts", p}, env, dir)
			if err2 := runStep("install scripts of "+p+" (retry without --allow-scripts)", c2); err2 != nil {
				return err2
			}
		}
	}
	return nil
}

func uvEnv(sc Scope) []string {
	return []string{
		"UV_PYTHON_INSTALL_DIR=" + filepath.Join(sc.Data, "python"),
		"UV_CACHE_DIR=" + filepath.Join(sc.Data, "cache", "uv"),
		"UV_NO_CONFIG=1",
		"UV_PYTHON_PREFERENCE=only-managed",
		"UV_LINK_MODE=copy",
	}
}

func installUvLock(sc Scope, e *Entry, rt *Installed, dir string) error {
	uv := runtimeBin(rt, "uv")
	lock := filepath.Join(locksDir(), e.Lock)
	if !exists(lock) {
		return fmt.Errorf("lock file %s is missing", lock)
	}
	env := helperEnv(sc, uvEnv(sc)...)
	w := []string{dir, filepath.Join(sc.Data, "python"), filepath.Join(sc.Data, "cache", "uv")}
	c := confined(w, true, []string{uv, "venv", "--python", e.Python, filepath.Join(dir, "venv")}, env, dir)
	if err := runStep("uv venv (Python "+e.Python+", sha256 checked by uv)", c); err != nil {
		return err
	}
	say("uv installs with --require-hashes from %s", lock)
	c = confined(w, true, []string{uv, "pip", "install", "--python", filepath.Join(dir, "venv", "bin", "python"), "--require-hashes", "--no-deps", "-r", lock}, env, dir)
	return runStep("uv pip install --require-hashes", c)
}

var hexRe = regexp.MustCompile(`^[0-9a-f]{40}$`)

func installGitUv(sc Scope, e *Entry, rt *Installed, dir string) error {
	if lookPath("git") == "" {
		return fmt.Errorf("%s needs git (sudo apt install git)", e.Name)
	}
	if !hexRe.MatchString(e.Commit) {
		return fmt.Errorf("catalog entry %s has no pinned commit", e.Name)
	}
	src := filepath.Join(dir, "src")
	env := helperEnv(sc, "GIT_TERMINAL_PROMPT=0", "GIT_CONFIG_NOSYSTEM=1")
	c := confined([]string{dir}, true, []string{"git", "clone", "--quiet", "--depth", "1", "--branch", e.Tag, "--single-branch", e.Git, src}, env, dir)
	if err := runStep("git clone "+e.Git+" "+e.Tag, c); err != nil {
		return err
	}
	out, err := exec.Command("git", "-C", src, "rev-parse", "HEAD").Output()
	if err != nil {
		return err
	}
	got := strings.TrimSpace(string(out))
	if got != e.Commit {
		return fmt.Errorf("%s: tag %s is commit %s, KwickOS pinned %s; nothing was installed", e.Name, e.Tag, got, e.Commit)
	}
	say("commit %s verified", got)
	uv := runtimeBin(rt, "uv")
	env = helperEnv(sc, append(uvEnv(sc), "UV_PROJECT_ENVIRONMENT="+filepath.Join(dir, "venv"))...)
	w := []string{dir, filepath.Join(sc.Data, "python"), filepath.Join(sc.Data, "cache", "uv")}
	c = confined(w, true, []string{uv, "sync", "--frozen", "--no-dev", "--python", e.Python, "--project", src}, env, src)
	return runStep("uv sync --frozen (hashes from the project's uv.lock)", c)
}

func cybaraLatest(arch string) (Asset, string, error) {
	aa := map[string]string{"amd64": "x64", "arm64": "arm64"}[arch]
	if aa == "" {
		return Asset{}, "", fmt.Errorf("no Cybara build for %s", arch)
	}
	body, err := fetchText("https://api.github.com/repos/metaspartan/cybara/releases/latest", 1<<20)
	if err != nil {
		return Asset{}, "", err
	}
	var rel struct {
		Tag string `json:"tag_name"`
	}
	if err := json.Unmarshal([]byte(body), &rel); err != nil || rel.Tag == "" {
		return Asset{}, "", fmt.Errorf("could not read the latest Cybara release")
	}
	url := fmt.Sprintf("https://github.com/metaspartan/cybara/releases/download/%s/cybara-%s-linux-%s-cli", rel.Tag, rel.Tag, aa)
	sum, err := fetchText(url+".sha256", 4096)
	if err != nil {
		return Asset{}, "", err
	}
	f := strings.Fields(sum)
	if len(f) == 0 || len(f[0]) != 64 {
		return Asset{}, "", fmt.Errorf("vendor checksum for %s is missing or malformed", rel.Tag)
	}
	return Asset{URL: url, SHA256: strings.ToLower(f[0]), Format: "raw"}, strings.TrimPrefix(rel.Tag, "v"), nil
}

func resolveNames(c *Catalog, names []string) ([]*Entry, error) {
	var out []*Entry
	for _, n := range names {
		e, err := c.get(n)
		if err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, nil
}

func cmdInstall(c *Catalog, o opts, pos []string) error {
	if len(pos) == 0 {
		return fmt.Errorf("usage: kwick-agents install NAME... (see: kwick-agents list)")
	}
	ents, err := resolveNames(c, pos)
	if err != nil {
		return err
	}
	if o.system && !isRoot() {
		return reexecRoot(os.Args[1:])
	}
	sc := installScope(o)
	unlock, err := lockScope(sc)
	if err != nil {
		return err
	}
	defer unlock()
	var failed []string
	for _, e := range ents {
		say("== %s %s (%s install)", e.Name, e.Version, sc.Name())
		st := loadState(sc)
		if err := installEntry(c, sc, st, e, o); err != nil {
			warnf("%s: %v", e.Name, err)
			failed = append(failed, e.Name)
			continue
		}
		if e.Kind != "runtime" && !sc.System && !o.noMCP && e.MCP != "" && e.MCP != "none" {
			if f, err := mcpEnable(e); err != nil {
				warnf("kwick-mcp was not registered with %s: %v", e.Name, err)
			} else if f != "" {
				say("kwick-mcp registered in %s (undo: kwick-agents mcp disable %s)", shortPath(f), e.Name)
			}
		}
		if e.FirstRun != "" {
			say("Next: %s", e.FirstRun)
		}
	}
	if len(failed) > 0 {
		return exitErr{1}
	}
	return nil
}

func cmdAll(c *Catalog, o opts) error {
	var names []string
	for _, e := range c.Entries {
		if e.Kind != "agent" || e.Hidden {
			continue
		}
		if ok, _ := c.supported(e, hostArch()); ok {
			names = append(names, e.Name)
		}
	}
	if len(names) == 0 {
		return fmt.Errorf("no agent is available on this machine")
	}
	return cmdInstall(c, o, names)
}

func removeEntry(c *Catalog, sc Scope, name string) error {
	st := loadState(sc)
	in, ok := st.Agents[name]
	if !ok {
		return fmt.Errorf("%s is not installed (%s)", name, sc.Name())
	}
	if e, ok := c.byName[name]; ok && e.Kind == "runtime" {
		var users []string
		for n, a := range st.Agents {
			if a.Runtime == name {
				users = append(users, n)
			}
		}
		if len(users) > 0 {
			sort.Strings(users)
			return fmt.Errorf("%s is used by %s; remove those first", name, strings.Join(users, ", "))
		}
	}
	if in.Legacy {
		os.Remove(filepath.Join(sysBin, "cybara"))
		os.Remove(filepath.Join(sysState, "cybara"))
	} else {
		for _, p := range in.Shims {
			if isOurShim(p) {
				os.Remove(p)
			}
		}
		if strings.HasPrefix(in.Dir, sc.Data+"/") {
			os.RemoveAll(filepath.Dir(in.Dir))
		}
	}
	delete(st.Agents, name)
	return saveState(sc, st)
}

func cmdRemove(c *Catalog, o opts, pos []string) error {
	if len(pos) == 0 {
		return fmt.Errorf("usage: kwick-agents remove NAME...")
	}
	ents, err := resolveNames(c, pos)
	if err != nil {
		return err
	}
	sc := installScope(o)
	if !o.system && !o.user && !isRoot() {
		for _, e := range ents {
			if _, ok := loadState(sc).Agents[e.Name]; !ok {
				if _, ok := loadState(systemScope()).Agents[e.Name]; ok {
					return fmt.Errorf("%s is installed for every user; remove it with: kwick-agents remove --system %s", e.Name, e.Name)
				}
			}
		}
	}
	if sc.System && !isRoot() {
		return reexecRoot(os.Args[1:])
	}
	unlock, err := lockScope(sc)
	if err != nil {
		return err
	}
	defer unlock()
	var failed bool
	for _, e := range ents {
		if err := removeEntry(c, sc, e.Name); err != nil {
			warnf("%v", err)
			failed = true
			continue
		}
		if !sc.System && e.Kind != "runtime" {
			mcpDisable(e)
		}
		say("%s removed; its data and settings in your home directory are kept (%s)", e.Name, strings.Join(e.Home, " "))
	}
	if failed {
		return exitErr{1}
	}
	return nil
}

type updateResult struct {
	Name  string `json:"name"`
	From  string `json:"from"`
	To    string `json:"to"`
	Scope string `json:"scope"`
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
}

func cmdUpdate(c *Catalog, o opts, pos []string) error {
	if o.system && !isRoot() {
		return reexecRoot(os.Args[1:])
	}
	sc := installScope(o)
	unlock, err := lockScope(sc)
	if err != nil {
		return err
	}
	defer unlock()
	st := loadState(sc)
	want := map[string]bool{}
	for _, n := range pos {
		e, err := c.get(n)
		if err != nil {
			return err
		}
		want[e.Name] = true
	}
	var names []string
	for n := range st.Agents {
		if len(want) == 0 || want[n] {
			names = append(names, n)
		}
	}
	sort.Slice(names, func(i, j int) bool {
		ei, ej := c.byName[names[i]], c.byName[names[j]]
		ri := ei != nil && ei.Kind == "runtime"
		rj := ej != nil && ej.Kind == "runtime"
		if ri != rj {
			return ri
		}
		return names[i] < names[j]
	})
	for n := range want {
		if _, ok := st.Agents[n]; !ok {
			warnf("%s is not installed (%s)", n, sc.Name())
		}
	}
	results := []updateResult{}
	failed := false
	for _, n := range names {
		e := c.byName[n]
		cur := st.Agents[n]
		if e == nil {
			continue
		}
		if cur.Version == e.Version && !cur.Legacy && !o.latest {
			continue
		}
		r := updateResult{Name: n, From: cur.Version, To: e.Version, Scope: sc.Name()}
		say("== %s %s -> %s", n, cur.Version, e.Version)
		if err := installEntry(c, sc, loadState(sc), e, o); err != nil {
			r.Error = err.Error()
			failed = true
			warnf("%s: %v", n, err)
		} else {
			r.OK = true
		}
		results = append(results, r)
	}
	if o.json {
		emitJSON(map[string]any{"schema": 1, "updated": results})
	} else if len(results) == 0 {
		say("Everything installed (%s) is at the pinned version.", sc.Name())
	}
	if failed {
		return exitErr{1}
	}
	return nil
}
