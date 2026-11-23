package main

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const (
	inferPort      = 11435
	inferAlias     = "local"
	inferKeyEnv    = "KWICK_INFERENCE_API_KEY"
	inferEntryName = "inference"
	inferIdleSecs  = 900
)

var (
	inferSystem  bool
	inferRawArgs []string
)

type iopts struct {
	json      bool
	fits      bool
	installed bool
	all       bool
	system    bool
	follow    bool
	yes       bool
	remote    bool
	noSandbox bool
	backend   string
	ctx       int
	n         int
	args      []string
}

func parseIopts(a []string) (iopts, error) {
	o := iopts{n: 100}
	for i := 0; i < len(a); i++ {
		s := a[i]
		val := func() (string, error) {
			if j := strings.IndexByte(s, '='); j > 0 && strings.HasPrefix(s, "--") {
				return s[j+1:], nil
			}
			if i+1 >= len(a) {
				return "", fmt.Errorf("%s needs a value", s)
			}
			i++
			return a[i], nil
		}
		name := s
		if j := strings.IndexByte(s, '='); j > 0 && strings.HasPrefix(s, "--") {
			name = s[:j]
		}
		var err error
		switch name {
		case "--json":
			o.json = true
		case "--fits":
			o.fits = true
		case "--installed":
			o.installed = true
		case "--all":
			o.all = true
		case "--system":
			o.system = true
		case "-f", "--follow":
			o.follow = true
		case "-y", "--yes":
			o.yes = true
		case "--remote":
			o.remote = true
		case "--no-sandbox":
			o.noSandbox = true
		case "--backend":
			o.backend, err = val()
		case "--ctx", "-c":
			var v string
			if v, err = val(); err == nil {
				o.ctx, err = strconv.Atoi(strings.TrimSuffix(strings.ToUpper(v), "K"))
				if err == nil && strings.HasSuffix(strings.ToUpper(v), "K") {
					o.ctx *= 1024
				}
				if err != nil || o.ctx < 0 {
					err = fmt.Errorf("--ctx needs a number of tokens")
				}
			}
		case "-n":
			var v string
			if v, err = val(); err == nil {
				o.n, err = strconv.Atoi(v)
			}
		default:
			if strings.HasPrefix(s, "-") && s != "-" {
				return o, fmt.Errorf("unknown option %s", s)
			}
			o.args = append(o.args, s)
		}
		if err != nil {
			return o, err
		}
	}
	return o, nil
}

func inferUsage() {
	fmt.Print(`usage: kwick-agents inference <command> [options]   (also: kwick-inference)

Local models on this machine: llama.cpp behind one OpenAI- and Anthropic-compatible endpoint
on http://127.0.0.1:11435/v1 with an API key, model name "local".

  status [--json]                     engine, backend, hardware, service, model and connected agents
  doctor [--json]                     check the engine, GPU access, sandbox, key and service
  gpu [--json]                        GPUs, VRAM, RAM and the memory budget for models
  install [--backend B] [--json]      download and verify llama.cpp for this GPU (cpu, vulkan, cuda12, cuda13, rocm)
  remove                              remove the engine (models are kept)
  update [--json]                     move the engine to the pinned build
  models [--json] [--fits] [--installed] [--ctx N]
                                      curated models with size, licence and whether they fit
  model pull ID|hf://REPO[:QUANT]     download a model, resume, verify its sha256 (uses the shared key HF_TOKEN for gated models)
  model cancel ID                     stop a download and keep the partial file for the next pull
  downloads [--json]                  downloads in progress: bytes done, total, rate
  model add hf://REPO[:QUANT]         pin a model from Hugging Face (commit, size and sha256)
  model rm ID | model verify [ID]
  use ID|best                         choose the model served as "local" (downloads it if needed)
  unload [ID]                         take the model out of memory; it loads again on the next request
  config [--json]                     idle unload and LAN access
  config set idle-minutes N|never     minutes without requests before the model leaves memory
  config set lan on|off               listen on all interfaces (still needs the key)
  bench [--json]                      llama-bench on the chosen model: prompt and generation tokens per second
  fit ID [--ctx N] [--json]           weights + KV cache + overhead against the memory budget
  service enable|disable|start|stop|restart|status|logs [-n N] [-f]
  connect [AGENT...|--all]            point agents at the local endpoint (opencode, codex, goose, hermes,
                                      openclaw, omp, cybara); undo with disconnect
  disconnect [AGENT...|--all]
  endpoint [--json]                   the endpoint file agents read (never the key)
  key rotate                          new API key; restarts the service and reconnects agents

kwick-agents run --local aider|claude-code points those agents at the local endpoint for one run.
KWICK_INFERENCE_BACKEND overrides the backend choice.
`)
}

func inferenceMain(a []string) int {
	inferRawArgs = a
	o, err := parseIopts(a)
	if err != nil {
		warnf("%v", err)
		return 2
	}
	if o.system {
		inferSystem = true
	}
	if len(o.args) == 0 {
		o.args = []string{"status"}
	}
	cmd, pos := o.args[0], o.args[1:]
	switch cmd {
	case "help", "-h", "--help":
		inferUsage()
		return 0
	case "status":
		err = cmdInferStatus(o)
	case "doctor":
		err = cmdInferDoctor(o)
	case "gpu", "hardware":
		err = cmdInferGPU(o)
	case "install":
		err = cmdInferInstall(o)
	case "remove", "uninstall":
		err = cmdInferRemove(o)
	case "update", "upgrade":
		err = cmdInferUpdate(o)
	case "models":
		err = cmdInferModels(o)
	case "model":
		err = cmdInferModel(o, pos)
	case "use":
		err = cmdInferUse(o, pos)
	case "unload":
		err = cmdInferUnload(o, pos)
	case "downloads":
		err = cmdInferDownloads(o)
	case "config":
		err = cmdInferConfig(o, pos)
	case "bench":
		err = cmdInferBench(o)
	case "fit":
		err = cmdInferFit(o, pos)
	case "service":
		return cmdInferService(o, pos)
	case "connect":
		err = cmdInferConnect(o, pos, true)
	case "disconnect":
		err = cmdInferConnect(o, pos, false)
	case "endpoint":
		err = cmdInferEndpoint(o)
	case "key":
		err = cmdInferKey(o, pos)
	default:
		warnf("unknown inference command %q (see: kwick-agents inference help)", cmd)
		return 2
	}
	if err != nil {
		var ee exitErr
		if errors.As(err, &ee) {
			return ee.code
		}
		warnf("%v", err)
		return 1
	}
	return 0
}

func inferScope() Scope {
	if inferSystem {
		return systemScope()
	}
	return userScope()
}

func inferConfigDir() string {
	if inferSystem {
		return "/etc/kwick-inference"
	}
	return filepath.Join(xdg("XDG_CONFIG_HOME", ".config"), "kwick-inference")
}

func inferModelsDir() string {
	if p := os.Getenv("KWICK_INFERENCE_MODELS_DIR"); p != "" && filepath.IsAbs(p) {
		return p
	}
	if inferSystem {
		return "/var/lib/kwick-inference/models"
	}
	return filepath.Join(xdg("XDG_DATA_HOME", ".local/share"), "kwick-inference", "models")
}

func inferRunDir() string {
	if inferSystem {
		return "/run/kwick-inference"
	}
	return filepath.Join(runtimeDir(), "inference")
}

func inferLogPath() string {
	if inferSystem {
		return "/var/log/kinit/kwick-inference.service.log"
	}
	return filepath.Join(userScope().State, "inference.log")
}

func endpointPath() string { return filepath.Join(inferConfigDir(), "endpoint.json") }

type connRecord struct {
	File     string         `json:"file,omitempty"`
	Previous map[string]any `json:"previous,omitempty"`
	ID       string         `json:"id,omitempty"`
	At       string         `json:"at"`
}

type inferConfig struct {
	Schema      int                    `json:"schema"`
	Backend     string                 `json:"backend,omitempty"`
	Model       string                 `json:"model,omitempty"`
	Ctx         int                    `json:"ctx,omitempty"`
	Port        int                    `json:"port,omitempty"`
	IdleSeconds int                    `json:"idle_seconds,omitempty"`
	Enabled     bool                   `json:"enabled"`
	Sandbox     *bool                  `json:"sandbox,omitempty"`
	LAN         bool                   `json:"lan,omitempty"`
	Connected   map[string]*connRecord `json:"connected,omitempty"`
}

func loadInferConfig() *inferConfig {
	c := &inferConfig{Schema: 1}
	readJSONFile(filepath.Join(inferConfigDir(), "config.json"), c)
	if c.Connected == nil {
		c.Connected = map[string]*connRecord{}
	}
	return c
}

func saveInferConfig(c *inferConfig) error {
	c.Schema = 1
	return writeJSONFile(filepath.Join(inferConfigDir(), "config.json"), c, 0o644)
}

func (c *inferConfig) port() int {
	if c.Port > 0 && c.Port < 65536 {
		return c.Port
	}
	return inferPort
}

func (c *inferConfig) idle() int {
	if c.IdleSeconds < 0 {
		return 0
	}
	if c.IdleSeconds != 0 {
		return c.IdleSeconds
	}
	return inferIdleSecs
}

func (c *inferConfig) ctx() int {
	if c.Ctx > 0 {
		return c.Ctx
	}
	return fitCtxFloor
}

func (c *inferConfig) sandbox() bool {
	if os.Getenv("KWICK_INFERENCE_NO_SANDBOX") == "1" {
		return false
	}
	return c.Sandbox == nil || *c.Sandbox
}

func (c *inferConfig) baseURL() string { return fmt.Sprintf("http://127.0.0.1:%d", c.port()) }

type inferState struct {
	Schema      int      `json:"schema"`
	Build       string   `json:"build"`
	Backend     string   `json:"backend"`
	Dir         string   `json:"dir"`
	InstalledAt string   `json:"installed_at"`
	SmokeOK     bool     `json:"smoke_ok"`
	Devices     []string `json:"devices"`
	SmokeError  string   `json:"smoke_error,omitempty"`
}

func inferStatePath(sc Scope) string { return filepath.Join(sc.State, "inference.json") }

func loadInferState() (*inferState, bool) {
	in, sc, ok := findInstalled(inferEntryName)
	if inferSystem {
		sc = systemScope()
		in, ok = loadState(sc).Agents[inferEntryName]
	}
	if !ok {
		return nil, false
	}
	var st inferState
	if readJSONFile(inferStatePath(sc), &st) != nil || st.Dir != in.Dir {
		st = inferState{Schema: 1, Build: in.Version, Dir: in.Dir}
		b := filepath.Base(in.Dir)
		if i := strings.LastIndex(b, "-"); i > 0 {
			st.Backend = b[i+1:]
		}
	}
	if !exists(filepath.Join(st.Dir, "llama-server")) {
		return &st, false
	}
	return &st, true
}

func inferEntry(c *Catalog) (*Entry, error) {
	e, ok := c.byName[inferEntryName]
	if !ok || len(e.Backends) == 0 {
		return nil, fmt.Errorf("the catalog has no inference engine entry")
	}
	return e, nil
}

func wantedBackend(o iopts) string {
	if o.backend != "" {
		return o.backend
	}
	if v := os.Getenv("KWICK_INFERENCE_BACKEND"); v != "" {
		return v
	}
	return loadInferConfig().Backend
}

func cmdInferInstall(o iopts) error {
	c, err := loadCatalog()
	if err != nil {
		return err
	}
	e, err := inferEntry(c)
	if err != nil {
		return err
	}
	if inferSystem && !isRoot() {
		return reexecRoot(append([]string{"inference"}, inferRawArgs...))
	}
	sc := inferScope()
	unlock, err := lockScope(sc)
	if err != nil {
		return err
	}
	defer unlock()
	st, err := inferInstall(c, e, sc, wantedBackend(o))
	if o.json {
		res := map[string]any{"schema": 1, "ok": err == nil, "engine": st}
		if err != nil {
			res["error"] = err.Error()
		}
		emitJSON(res)
	}
	if err == nil && o.backend != "" {
		cfg := loadInferConfig()
		cfg.Backend = o.backend
		saveInferConfig(cfg)
	}
	return err
}

func inferInstallEntry(c *Catalog, sc Scope, e *Entry, o opts) error {
	b := os.Getenv("KWICK_INFERENCE_BACKEND")
	if b == "" {
		if cur, ok := loadInferState(); ok {
			b = cur.Backend
		}
	}
	_, err := inferInstall(c, e, sc, b)
	return err
}

func inferInstall(c *Catalog, e *Entry, sc Scope, backend string) (*inferState, error) {
	arch := hostArch()
	if ok, why := c.supported(e, arch); !ok {
		return nil, fmt.Errorf("the inference engine is not available here: %s", why)
	}
	hw := detectHardware()
	ch, err := selectBackend(e, hw, backend, vulkanICD())
	if err != nil {
		return nil, err
	}
	ba := e.Backends[ch.Backend][arch]
	say("== llama.cpp %s, backend %s (%s)", e.Version, ch.Backend, ch.Reason)
	if ch.Backend == "rocm" && !hipRuntime() {
		return nil, fmt.Errorf("the ROCm build needs the ROCm 7 runtime (libamdhip64.so.7, librocblas.so.5, libhipblas.so.3), which Debian 13 does not ship; use --backend vulkan")
	}
	dir := filepath.Join(sc.Data, "pkgs", inferEntryName, e.Version+"-"+ch.Backend)
	if cur, ok := loadInferState(); ok && cur.Dir == dir && cur.SmokeOK {
		say("llama.cpp %s (%s) is already installed in %s", e.Version, ch.Backend, shortPath(dir))
		return cur, nil
	}
	tmp := dir + ".new"
	os.RemoveAll(tmp)
	if err := os.MkdirAll(tmp, 0o755); err != nil {
		return nil, err
	}
	ok := false
	defer func() {
		if !ok {
			os.RemoveAll(tmp)
		}
	}()
	dl := filepath.Join(sc.Data, "downloads")
	assets := []Asset{ba.Asset}
	if ba.Runtime != nil {
		assets = append(assets, *ba.Runtime)
	}
	for _, a := range assets {
		say("Downloading %s (%s)", a.URL, humanBytes(a.Size))
		say("Expected sha256 %s", a.SHA256)
		file := filepath.Join(dl, a.SHA256)
		if err := download(a.URL, a.SHA256, a.Size, file); err != nil {
			return nil, err
		}
		say("sha256 verified")
		if err := extract(file, a.Format, tmp, a.Strip, a.Rename); err != nil {
			return nil, err
		}
		os.Remove(file)
	}
	if !exists(filepath.Join(tmp, "llama-server")) {
		return nil, fmt.Errorf("llama-server is missing from the archive")
	}
	os.RemoveAll(dir)
	if err := os.Rename(tmp, dir); err != nil {
		return nil, err
	}
	st := &inferState{Schema: 1, Build: e.Version, Backend: ch.Backend, Dir: dir, InstalledAt: nowStamp()}
	say("-> smoke test in the sandbox: ldd and llama-server --list-devices")
	devs, serr := smokeTest(dir, ch.Backend)
	st.Devices = devs
	if serr != nil {
		st.SmokeError = serr.Error()
		os.RemoveAll(dir)
		return st, fmt.Errorf("smoke test failed: %v", serr)
	}
	st.SmokeOK = true
	if ch.Backend != "cpu" && len(devs) == 0 {
		warnf("llama-server sees no %s device; it will run on the CPU until the GPU driver works (kwick-agents inference doctor)", ch.Backend)
	}
	for _, d := range devs {
		say("   device %s", d)
	}
	state := loadState(sc)
	old := state.Agents[inferEntryName]
	state.Agents[inferEntryName] = &Installed{Name: inferEntryName, Version: e.Version, Method: e.Method, Dir: dir, Commands: []string{}, InstalledAt: nowStamp(), Scope: sc.Name()}
	if err := saveState(sc, state); err != nil {
		return st, err
	}
	if err := writeJSONFile(inferStatePath(sc), st, 0o644); err != nil {
		return st, err
	}
	ok = true
	if old != nil && old.Dir != dir && strings.HasPrefix(old.Dir, sc.Data+"/") {
		os.RemoveAll(old.Dir)
	}
	say("llama.cpp %s (%s) installed in %s", e.Version, ch.Backend, shortPath(dir))
	return st, nil
}

func smokeTest(dir, backend string) ([]string, error) {
	lib := map[string]string{"cuda12": "libggml-cuda.so", "cuda13": "libggml-cuda.so", "rocm": "libggml-hip.so", "vulkan": "libggml-vulkan.so"}[backend]
	targets := []string{filepath.Join(dir, "llama-server")}
	if lib != "" {
		targets = append(targets, filepath.Join(dir, lib))
	}
	cfg := loadInferConfig()
	for _, t := range targets {
		if !exists(t) {
			return nil, fmt.Errorf("%s is missing", filepath.Base(t))
		}
		out, _ := sandboxCmd(cfg, dir, "", backend, []string{"/usr/bin/ldd", t}).CombinedOutput()
		var missing []string
		for _, l := range strings.Split(string(out), "\n") {
			if strings.Contains(l, "not found") {
				missing = append(missing, strings.TrimSpace(strings.Split(l, "=>")[0]))
			}
		}
		if len(missing) > 0 {
			return nil, fmt.Errorf("%s needs %s%s", filepath.Base(t), strings.Join(missing, ", "), missingHint(missing))
		}
	}
	out, err := sandboxCmd(cfg, dir, "", backend, []string{filepath.Join(dir, "llama-server"), "--list-devices"}).CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("llama-server --list-devices: %v: %s", err, lastLines(string(out), 6))
	}
	var devs []string
	in := false
	for _, l := range strings.Split(string(out), "\n") {
		if strings.HasPrefix(l, "Available devices") {
			in = true
			continue
		}
		t := strings.TrimSpace(l)
		if in && t != "" && t != "(none)" {
			devs = append(devs, t)
		}
	}
	if !in {
		return nil, fmt.Errorf("llama-server --list-devices printed no device list: %s", lastLines(string(out), 6))
	}
	if devs == nil {
		devs = []string{}
	}
	return devs, nil
}

func missingHint(m []string) string {
	j := strings.Join(m, " ")
	switch {
	case strings.Contains(j, "libcuda.so"):
		return " (the NVIDIA driver is not installed or not loaded: kwick-gpu install)"
	case strings.Contains(j, "libamdhip64") || strings.Contains(j, "rocblas"):
		return " (the ROCm 7 runtime is not installed; use --backend vulkan)"
	case strings.Contains(j, "libvulkan"):
		return " (sudo apt install libvulkan1 mesa-vulkan-drivers)"
	case strings.Contains(j, "libgomp"):
		return " (sudo apt install libgomp1)"
	}
	return ""
}

func lastLines(s string, n int) string {
	l := strings.Split(strings.TrimSpace(s), "\n")
	if len(l) > n {
		l = l[len(l)-n:]
	}
	return strings.Join(l, " | ")
}

func cmdInferRemove(o iopts) error {
	if inferSystem && !isRoot() {
		return reexecRoot(append([]string{"inference"}, inferRawArgs...))
	}
	c, err := loadCatalog()
	if err != nil {
		return err
	}
	if serviceRunning() {
		stopService()
	}
	sc := inferScope()
	unlock, err := lockScope(sc)
	if err != nil {
		return err
	}
	defer unlock()
	if err := removeEntry(c, sc, inferEntryName); err != nil {
		return err
	}
	os.Remove(inferStatePath(sc))
	say("llama.cpp removed; models in %s and settings in %s are kept", shortPath(inferModelsDir()), shortPath(inferConfigDir()))
	return nil
}

func cmdInferUpdate(o iopts) error {
	c, err := loadCatalog()
	if err != nil {
		return err
	}
	e, err := inferEntry(c)
	if err != nil {
		return err
	}
	cur, ok := loadInferState()
	if !ok {
		return fmt.Errorf("the engine is not installed (kwick-agents inference install)")
	}
	from := cur.Build
	b := wantedBackend(o)
	if b == "" {
		b = cur.Backend
	}
	sc := inferScope()
	unlock, err := lockScope(sc)
	if err != nil {
		return err
	}
	var st *inferState
	if cur.Build == e.Version && cur.Backend == b && cur.SmokeOK {
		st = cur
		say("llama.cpp %s (%s) is the pinned build", cur.Build, cur.Backend)
	} else {
		st, err = inferInstall(c, e, sc, b)
	}
	unlock()
	if err == nil && from != e.Version && serviceRunning() {
		restartService()
	}
	if o.json {
		r := map[string]any{"name": inferEntryName, "from": from, "to": e.Version, "scope": sc.Name(), "ok": err == nil}
		if err != nil {
			r["error"] = err.Error()
		}
		if st != nil {
			r["backend"] = st.Backend
		}
		emitJSON(map[string]any{"schema": 1, "updated": []any{r}})
	}
	return err
}

func cmdInferUse(o iopts, pos []string) error {
	if len(pos) != 1 {
		return fmt.Errorf("usage: kwick-agents inference use ID|best")
	}
	mc, err := loadModelCatalog()
	if err != nil {
		return err
	}
	hw := detectHardware()
	cfg := loadInferConfig()
	id := pos[0]
	if id == "best" {
		items := modelItems(mc, hw, int64(o.ctx), cfg, false)
		for _, it := range items {
			if it.Recommended {
				id = it.ID
				say("Best model for this machine: %s (%s, %s)", it.ID, humanBytes(it.Size), it.Fit.Reason)
			}
		}
		if id == "best" {
			return fmt.Errorf("no model in the catalog fits this machine (kwick-agents inference models)")
		}
	}
	m, err := mc.find(id)
	if err != nil {
		return err
	}
	if sh, err := modelShape(m); err == nil {
		f := computeFit(sh, hw, int64(o.ctx))
		if f.Verdict == "no" {
			warnf("%s probably does not fit: %s", m.ID, f.Reason)
		}
	}
	if inst, _ := installedModel(m); !inst {
		say("%s is not downloaded yet: %s, licence %s", m.ID, humanBytes(m.size()), m.License)
		if err := pullModel(m); err != nil {
			return err
		}
	}
	cfg.Model = m.ID
	if o.ctx > 0 {
		cfg.Ctx = o.ctx
	}
	if err := saveInferConfig(cfg); err != nil {
		return err
	}
	if err := writeEndpoint(cfg); err != nil {
		return err
	}
	say("%s is now the model \"local\" (%s)", m.ID, shortPath(modelPath(m)))
	if serviceRunning() {
		return restartService()
	}
	say("Start the endpoint with: kwick-agents inference service start")
	return nil
}

func randomKey() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return "kwi-" + hex.EncodeToString(b), nil
}

func systemKeyPath() string { return "/etc/kwick-inference/api-key" }

func inferKey(create bool) (string, error) {
	if inferSystem {
		b, err := os.ReadFile(systemKeyPath())
		if err == nil && len(strings.TrimSpace(string(b))) > 0 {
			return strings.TrimSpace(string(b)), nil
		}
		if !create {
			return "", fmt.Errorf("no API key in %s", systemKeyPath())
		}
		k, err := randomKey()
		if err != nil {
			return "", err
		}
		os.MkdirAll(filepath.Dir(systemKeyPath()), 0o755)
		if err := writeFileAtomic(systemKeyPath(), []byte(k+"\n"), 0o640); err != nil {
			return "", err
		}
		if lookPath("chgrp") != "" {
			exec.Command("chgrp", "kwick-inference", systemKeyPath()).Run()
		}
		return k, nil
	}
	if b := loadKeyIndex()["shared"][inferKeyEnv]; b != "" {
		if v, ok := secretGet("shared", inferKeyEnv, b); ok && v != "" {
			return v, nil
		}
	}
	if !create {
		return "", fmt.Errorf("no API key stored (kwick-agents inference service start creates one)")
	}
	k, err := randomKey()
	if err != nil {
		return "", err
	}
	backend, err := secretSet("shared", inferKeyEnv, k)
	if err != nil {
		return "", err
	}
	auditLog(auditEntry{Agent: "shared", Tool: "cli", Capability: "keys", Decision: "set", OK: true, Summary: "created " + inferKeyEnv + " in " + backend})
	say("Created the local endpoint key %s in the keystore (%s); every agent gets it as an environment variable", inferKeyEnv, backend)
	return k, nil
}

func keyStored() bool {
	if inferSystem {
		return exists(systemKeyPath())
	}
	return loadKeyIndex()["shared"][inferKeyEnv] != ""
}

func cmdInferKey(o iopts, pos []string) error {
	if len(pos) != 1 || pos[0] != "rotate" {
		return fmt.Errorf("usage: kwick-agents inference key rotate")
	}
	k, err := randomKey()
	if err != nil {
		return err
	}
	if inferSystem {
		if err := writeFileAtomic(systemKeyPath(), []byte(k+"\n"), 0o640); err != nil {
			return err
		}
		exec.Command("chgrp", "kwick-inference", systemKeyPath()).Run()
	} else if _, err := secretSet("shared", inferKeyEnv, k); err != nil {
		return err
	}
	auditLog(auditEntry{Agent: "shared", Tool: "cli", Capability: "keys", Decision: "rotate", OK: true, Summary: "rotated " + inferKeyEnv})
	say("%s rotated", inferKeyEnv)
	cfg := loadInferConfig()
	if _, ok := cfg.Connected["cybara"]; ok {
		if err := connectAgent(cfg, "cybara", true); err != nil {
			warnf("cybara: %v", err)
		}
		saveInferConfig(cfg)
	}
	if serviceRunning() {
		return restartService()
	}
	return nil
}

type endpointInfo struct {
	Schema       int    `json:"schema"`
	URL          string `json:"url"`
	AnthropicURL string `json:"anthropic_url"`
	Model        string `json:"model"`
	ModelID      string `json:"model_id"`
	KeyEnv       string `json:"key_env"`
	KeySource    string `json:"key_source"`
	Context      int    `json:"context"`
	OpenAI       bool   `json:"openai_compatible"`
	Anthropic    bool   `json:"anthropic_compatible"`
	Engine       string `json:"engine"`
	Updated      string `json:"updated"`
}

func endpointFor(cfg *inferConfig) endpointInfo {
	src := "kwick-agents keystore, shared key " + inferKeyEnv + " (given to every agent kwick-agents starts)"
	if inferSystem {
		src = systemKeyPath() + " (group kwick-inference)"
	}
	return endpointInfo{Schema: 1, URL: cfg.baseURL() + "/v1", AnthropicURL: cfg.baseURL(), Model: inferAlias, ModelID: cfg.Model,
		KeyEnv: inferKeyEnv, KeySource: src, Context: cfg.ctx(), OpenAI: true, Anthropic: true, Engine: "llama.cpp", Updated: nowStamp()}
}

func writeEndpoint(cfg *inferConfig) error {
	return writeJSONFile(endpointPath(), endpointFor(cfg), 0o644)
}

func cmdInferEndpoint(o iopts) error {
	ep := endpointFor(loadInferConfig())
	if o.json {
		emitJSON(ep)
		return nil
	}
	fmt.Printf("OpenAI-compatible:    %s\nAnthropic-compatible: %s/v1/messages\nModel:                %s (%s)\nKey:                  $%s (%s)\nFile:                 %s\n",
		ep.URL, ep.AnthropicURL, ep.Model, ep.ModelID, ep.KeyEnv, ep.KeySource, endpointPath())
	return nil
}

type issue struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type engineStatus struct {
	Name            string   `json:"name"`
	PinnedBuild     string   `json:"pinned_build"`
	Installed       bool     `json:"installed"`
	Build           string   `json:"build,omitempty"`
	Backend         string   `json:"backend,omitempty"`
	UpdateAvailable bool     `json:"update_available"`
	Dir             string   `json:"dir,omitempty"`
	SmokeOK         bool     `json:"smoke_ok"`
	Devices         []string `json:"devices"`
}

type backendStatus struct {
	Recommended  string   `json:"recommended"`
	Reason       string   `json:"reason"`
	Override     string   `json:"override,omitempty"`
	Available    []string `json:"available"`
	DownloadSize int64    `json:"download_size"`
}

type agentConn struct {
	Name      string `json:"name"`
	Title     string `json:"title"`
	Installed bool   `json:"installed"`
	Supported bool   `json:"supported"`
	Connected bool   `json:"connected"`
	Method    string `json:"method"`
	File      string `json:"file,omitempty"`
	Note      string `json:"note,omitempty"`
}

type inferStatus struct {
	Schema       int            `json:"schema"`
	Scope        string         `json:"scope"`
	Engine       engineStatus   `json:"engine"`
	Backend      backendStatus  `json:"backend"`
	Hardware     Hardware       `json:"hardware"`
	Service      serviceStatus  `json:"service"`
	Model        *ModelItem     `json:"model"`
	Models       map[string]any `json:"models"`
	EndpointFile string         `json:"endpoint_file"`
	Agents       []agentConn    `json:"agents"`
	Issues       []issue        `json:"issues"`
	Memory       *memInfo       `json:"memory"`
	HFToken      bool           `json:"hf_token"`
	Bench        *benchResult   `json:"bench"`
}

func buildStatus() inferStatus {
	s := inferStatus{Schema: 1, Scope: inferScope().Name(), EndpointFile: endpointPath(), Issues: []issue{}}
	cfg := loadInferConfig()
	hw := detectHardware()
	s.Hardware = hw
	c, cerr := loadCatalog()
	var e *Entry
	if cerr == nil {
		e, cerr = inferEntry(c)
	}
	s.Engine = engineStatus{Name: "llama.cpp", Devices: []string{}}
	s.Backend.Available = []string{}
	if cerr != nil {
		s.Issues = append(s.Issues, issue{"catalog", cerr.Error()})
	} else {
		s.Engine.PinnedBuild = e.Version
		s.Backend.Available = backendList(e, hw.Arch)
		s.Backend.Override = wantedBackend(iopts{})
		ch, err := selectBackend(e, hw, "", vulkanICD())
		if err != nil {
			s.Issues = append(s.Issues, issue{"backend", err.Error()})
		} else {
			s.Backend.Recommended, s.Backend.Reason = ch.Backend, ch.Reason
			b := ch.Backend
			if s.Backend.Override != "" {
				b = s.Backend.Override
			}
			if ba, ok := e.Backends[b][hw.Arch]; ok {
				s.Backend.DownloadSize = ba.Size
				if ba.Runtime != nil {
					s.Backend.DownloadSize += ba.Runtime.Size
				}
			}
		}
	}
	if st, ok := loadInferState(); ok {
		s.Engine.Installed = true
		s.Engine.Build, s.Engine.Backend, s.Engine.Dir, s.Engine.SmokeOK = st.Build, st.Backend, st.Dir, st.SmokeOK
		if st.Devices != nil {
			s.Engine.Devices = st.Devices
		}
		s.Engine.UpdateAvailable = e != nil && st.Build != e.Version
		if s.Backend.Recommended != "" && s.Backend.Override == "" && st.Backend != s.Backend.Recommended {
			s.Issues = append(s.Issues, issue{"backend-mismatch", fmt.Sprintf("installed backend %s, recommended %s (kwick-agents inference install --backend %s)", st.Backend, s.Backend.Recommended, s.Backend.Recommended)})
		}
	} else {
		s.Issues = append(s.Issues, issue{"engine-missing", "the engine is not installed (kwick-agents inference install)"})
	}
	s.Service = getServiceStatus(cfg)
	mc, merr := loadModelCatalog()
	n, bytes := 0, int64(0)
	if merr == nil {
		for _, m := range mc.Models {
			if inst, _ := installedModel(m); inst {
				n++
				bytes += m.size()
			}
		}
		if cfg.Model != "" {
			if m, err := mc.find(cfg.Model); err == nil {
				it := ModelItem{ModelEntry: *m, Size: m.size(), MoE: m.moe(), Current: true}
				it.Shape = nil
				it.Installed, it.Verified = installedModel(m)
				it.trackDownload(m)
				if sh, err := modelShape(m); err == nil {
					f := computeFit(sh, hw, int64(cfg.ctx()))
					it.Fit = &f
					it.ContextMax = sh.ContextMax
					if f.Verdict == "no" {
						s.Issues = append(s.Issues, issue{"model-too-big", m.ID + ": " + f.Reason})
					}
				}
				if !it.Installed {
					s.Issues = append(s.Issues, issue{"model-missing", m.ID + " is selected but not downloaded (kwick-agents inference model pull " + m.ID + ")"})
				}
				s.Model = &it
			}
		} else {
			s.Issues = append(s.Issues, issue{"no-model", "no model selected (kwick-agents inference use best)"})
		}
	} else {
		s.Issues = append(s.Issues, issue{"models-catalog", merr.Error()})
	}
	s.Models = map[string]any{"installed": n, "bytes": bytes, "dir": inferModelsDir()}
	s.Agents = agentConnections(c, cfg)
	s.HFToken = hfTokenSet()
	if s.Model != nil {
		s.Bench = lastBench()
		if s.Bench != nil && s.Bench.Model != s.Model.ID {
			s.Bench = nil
		}
	}
	if s.Service.Running && !inferSystem {
		s.Memory = measureMemory(s.Service.PID, len(s.Service.Loaded) > 0, hw, s.Engine.Backend)
	}
	if s.Service.Enabled && !s.Service.Running {
		s.Issues = append(s.Issues, issue{"service-down", "the service is enabled but not running (kwick-agents inference service logs)"})
	}
	return s
}

func cmdInferStatus(o iopts) error {
	s := buildStatus()
	if o.json {
		emitJSON(s)
		return nil
	}
	if s.Engine.Installed {
		fmt.Printf("Engine:   llama.cpp %s, backend %s%s\n", s.Engine.Build, s.Engine.Backend, map[bool]string{true: " (update available: " + s.Engine.PinnedBuild + ")", false: ""}[s.Engine.UpdateAvailable])
	} else {
		fmt.Printf("Engine:   not installed (pinned llama.cpp %s)\n", s.Engine.PinnedBuild)
	}
	fmt.Printf("Backend:  %s recommended: %s\n", s.Backend.Recommended, s.Backend.Reason)
	fmt.Printf("Memory:   %d MB RAM, %d MB budget for models (%s)\n", s.Hardware.RAMMB, s.Hardware.MemoryBudgetMB, s.Hardware.Accelerator)
	for _, d := range s.Hardware.Devices {
		fmt.Printf("GPU %d:    %s %s, %d MB VRAM, driver %s %s\n", d.Index, d.Vendor, d.Name, d.VRAMMB, d.Driver, d.DriverVersion)
	}
	st := "stopped"
	if s.Service.Running {
		st = "running"
		if s.Service.Healthy {
			st += ", healthy"
		}
	}
	fmt.Printf("Service:  %s, %s; enabled at login: %v\n", st, s.Service.URL, s.Service.Enabled)
	if s.Service.LAN {
		fmt.Printf("Network:  open to other devices on %s:%d, key required\n", s.Service.Host, s.Service.Port)
	}
	if m := s.Memory; m != nil && m.Measured {
		what := "GPU memory"
		if m.Kind == "ram" {
			what = "memory"
		}
		fmt.Printf("In use:   %d of %d MB %s (measured by %s)\n", m.UsedMB, m.TotalMB, what, m.Source)
	}
	if s.Model != nil {
		v := ""
		if s.Model.Fit != nil {
			v = ", " + s.Model.Fit.Verdict
		}
		fmt.Printf("Model:    %s as \"local\" (%s%s)\n", s.Model.ID, humanBytes(s.Model.Size), v)
	} else {
		fmt.Println("Model:    none selected")
	}
	var conn []string
	for _, a := range s.Agents {
		if a.Connected {
			conn = append(conn, a.Name)
		}
	}
	if len(conn) > 0 {
		fmt.Printf("Agents:   %s\n", strings.Join(conn, ", "))
	}
	for _, i := range s.Issues {
		fmt.Printf("! %s\n", i.Message)
	}
	return nil
}

func cmdInferDoctor(o iopts) error {
	var cs []check
	add := func(n string, ok bool, d string) { cs = append(cs, check{n, ok, d}) }
	arch := hostArch()
	c, err := loadCatalog()
	var e *Entry
	if err == nil {
		e, err = inferEntry(c)
	}
	if err != nil {
		add("catalog", false, err.Error())
	} else {
		bl := backendList(e, arch)
		add("arch", len(bl) > 0, arch+": "+strings.Join(bl, ", "))
	}
	hw := detectHardware()
	add("memory", hw.RAMMB > 0, fmt.Sprintf("%d MB RAM, %d MB budget for models (%s)", hw.RAMMB, hw.MemoryBudgetMB, hw.Accelerator))
	for _, d := range hw.Devices {
		add(fmt.Sprintf("gpu %d", d.Index), true, fmt.Sprintf("%s %s, %d MB VRAM, %d MB GTT, driver %s %s", d.Vendor, d.Name, d.VRAMMB, d.GTTMB, d.Driver, d.DriverVersion))
	}
	if e != nil {
		ch, err := selectBackend(e, hw, wantedBackend(iopts{}), vulkanICD())
		if err != nil {
			add("backend", false, err.Error())
		} else {
			add("backend", true, ch.Backend+": "+ch.Reason)
			switch ch.Backend {
			case "cuda12", "cuda13":
				ok := exists("/dev/nvidiactl") && libPresent("libcuda.so.1")
				add("nvidia driver", ok, "needs /dev/nvidiactl and libcuda.so.1 from the NVIDIA driver")
			case "vulkan":
				add("vulkan driver", vulkanICD() && libPresent("libvulkan.so.1"), "needs libvulkan1 and an ICD in /usr/share/vulkan/icd.d")
			case "rocm":
				add("rocm runtime", hipRuntime(), "needs libamdhip64.so.7 and librocblas.so.5 (ROCm 7)")
			}
			if ch.Backend != "cpu" {
				rd, _ := filepath.Glob("/dev/dri/renderD*")
				okDev := false
				for _, r := range rd {
					if f, err := os.OpenFile(r, os.O_RDWR, 0); err == nil {
						f.Close()
						okDev = true
					}
				}
				if ch.Backend == "cuda12" || ch.Backend == "cuda13" {
					okDev = exists("/dev/nvidia0")
				}
				add("gpu access", okDev, "the user can open the GPU device nodes (groups render and video)")
			}
		}
	}
	st, inst := loadInferState()
	if inst {
		add("engine", st.SmokeOK, fmt.Sprintf("llama.cpp %s %s in %s; devices: %s %s", st.Build, st.Backend, shortPath(st.Dir), strings.Join(st.Devices, "; "), st.SmokeError))
	} else {
		add("engine", false, "not installed (kwick-agents inference install)")
	}
	cfg := loadInferConfig()
	if cfg.sandbox() {
		bw := lookPath("bwrap")
		if bw == "" {
			add("sandbox", false, "bubblewrap is not installed (sudo apt install bubblewrap)")
		} else if out, err := exec.Command(bw, "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc", "--unshare-all", "--share-net", "--die-with-parent", "--new-session", "true").CombinedOutput(); err != nil {
			add("sandbox", false, "bubblewrap cannot create a sandbox: "+strings.TrimSpace(string(out)))
		} else {
			add("sandbox", true, "llama-server runs in bubblewrap: GPU devices and the models folder read-only, no home, no D-Bus")
		}
	} else {
		add("sandbox", false, "turned off in "+shortPath(filepath.Join(inferConfigDir(), "config.json"))+" or KWICK_INFERENCE_NO_SANDBOX=1")
	}
	md := inferModelsDir()
	add("models folder", true, fmt.Sprintf("%s, %s free", shortPath(md), humanBytes(freeBytes(md))))
	if cfg.Model == "" {
		add("model", false, "none selected (kwick-agents inference use best)")
	} else if mc, err := loadModelCatalog(); err == nil {
		if m, err := mc.find(cfg.Model); err != nil {
			add("model", false, err.Error())
		} else {
			inst, ver := installedModel(m)
			d := m.ID
			if sh, err := modelShape(m); err == nil {
				f := computeFit(sh, hw, int64(cfg.ctx()))
				d += ": " + f.Verdict + ", " + f.Reason
			}
			add("model", inst && ver, d)
		}
	}
	add("api key", keyStored(), inferKeyEnv+" in the keystore (created by service start)")
	ss := getServiceStatus(cfg)
	if ss.Running {
		add("service", ss.Healthy, fmt.Sprintf("pid %d on %s", ss.PID, ss.URL))
	} else if portBusy(cfg.port()) {
		add("service", false, fmt.Sprintf("port %d is used by another program", cfg.port()))
	} else {
		add("service", true, "stopped (kwick-agents inference service start)")
	}
	failed := false
	for _, x := range cs {
		if !x.OK {
			failed = true
		}
	}
	if o.json {
		emitJSON(map[string]any{"schema": 1, "ok": !failed, "checks": cs})
	} else {
		for _, x := range cs {
			m := "ok  "
			if !x.OK {
				m = "FAIL"
			}
			fmt.Printf("%s %-14s %s\n", m, x.Name, x.Detail)
		}
	}
	if failed {
		return exitErr{1}
	}
	return nil
}

func libPresent(name string) bool {
	out, err := runTimeout(5*time.Second, "/sbin/ldconfig", "-p")
	if err == nil && strings.Contains(string(out), name) {
		return true
	}
	for _, d := range []string{"/usr/lib/x86_64-linux-gnu", "/usr/lib/aarch64-linux-gnu", "/usr/lib64", "/usr/lib"} {
		if exists(filepath.Join(d, name)) {
			return true
		}
	}
	return false
}
