package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
)

const hfTokenEnv = "HF_TOKEN"

func hfHost(host string) bool {
	if h, _, err := net.SplitHostPort(host); err == nil {
		host = h
	}
	if host == "huggingface.co" {
		return true
	}
	if i := strings.Index(hfAPIBase, "://"); i >= 0 {
		b := hfAPIBase[i+3:]
		if h, _, err := net.SplitHostPort(b); err == nil {
			b = h
		}
		return b == host && hfAPIBase != "https://huggingface.co"
	}
	return false
}

func hfTokenSet() bool {
	return loadKeyIndex()["shared"][hfTokenEnv] != "" || strings.TrimSpace(os.Getenv(hfTokenEnv)) != ""
}

func hfToken() string {
	if b := loadKeyIndex()["shared"][hfTokenEnv]; b != "" {
		if v, ok := secretGet("shared", hfTokenEnv, b); ok && strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
	}
	return strings.TrimSpace(os.Getenv(hfTokenEnv))
}

func hfAuth(req *http.Request) {
	if !hfHost(req.URL.Host) {
		return
	}
	if t := hfToken(); t != "" {
		req.Header.Set("Authorization", "Bearer "+t)
	}
}

func dropForeignAuth(req *http.Request, via []*http.Request) error {
	if len(via) >= 10 {
		return fmt.Errorf("stopped after 10 redirects")
	}
	if len(via) > 0 && req.URL.Host != via[0].URL.Host {
		req.Header.Del("Authorization")
	}
	return nil
}

func lanAddress() string {
	ifs, err := net.Interfaces()
	if err != nil {
		return ""
	}
	first := ""
	for _, ifc := range ifs {
		if ifc.Flags&net.FlagUp == 0 || ifc.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := ifc.Addrs()
		for _, a := range addrs {
			ipn, ok := a.(*net.IPNet)
			if !ok {
				continue
			}
			ip := ipn.IP.To4()
			if ip == nil || ip.IsLinkLocalUnicast() {
				continue
			}
			if ip.IsPrivate() {
				return ip.String()
			}
			if first == "" {
				first = ip.String()
			}
		}
	}
	return first
}

func (c *inferConfig) host() string {
	if c.LAN {
		return "0.0.0.0"
	}
	return "127.0.0.1"
}

func configInfo(cfg *inferConfig) map[string]any {
	m := map[string]any{"idle_seconds": cfg.idle(), "idle_minutes": cfg.idle() / 60, "lan": cfg.LAN, "host": cfg.host(), "port": cfg.port(), "ctx": cfg.ctx(), "model": cfg.Model}
	if cfg.LAN {
		if a := lanAddress(); a != "" {
			m["lan_url"] = fmt.Sprintf("http://%s:%d/v1", a, cfg.port())
		}
	}
	return m
}

func parseOnOff(s string) (bool, bool) {
	switch strings.ToLower(s) {
	case "on", "true", "yes", "1", "enable":
		return true, true
	case "off", "false", "no", "0", "disable":
		return false, true
	}
	return false, false
}

func cmdInferConfig(o iopts, pos []string) error {
	cfg := loadInferConfig()
	if len(pos) == 0 || pos[0] == "show" || pos[0] == "get" {
		if o.json {
			emitJSON(map[string]any{"schema": 1, "config": configInfo(cfg)})
			return nil
		}
		idle := "never"
		if cfg.idle() > 0 {
			idle = fmt.Sprintf("%d minutes", cfg.idle()/60)
		}
		fmt.Printf("Idle unload: %s\nLAN access:  %v (listens on %s:%d)\n", idle, cfg.LAN, cfg.host(), cfg.port())
		return nil
	}
	if pos[0] != "set" || len(pos) != 3 {
		return fmt.Errorf("usage: kwick-agents inference config [show] | set idle-minutes N|never | set lan on|off")
	}
	if inferSystem && !isRoot() {
		return reexecRoot(append([]string{"inference"}, inferRawArgs...))
	}
	changed := false
	switch pos[1] {
	case "idle-minutes", "idle":
		want := -1
		if v := strings.ToLower(pos[2]); v != "never" && v != "off" && v != "0" {
			n, err := strconv.Atoi(v)
			if err != nil || n < 1 || n > 1440 {
				return fmt.Errorf("idle-minutes needs a number from 1 to 1440, or never")
			}
			want = n * 60
		}
		changed = cfg.IdleSeconds != want && !(cfg.IdleSeconds == 0 && want == inferIdleSecs)
		cfg.IdleSeconds = want
		if want < 0 {
			say("The model stays in memory until the service stops")
		} else {
			say("The model leaves memory after %d minutes without requests", want/60)
		}
	case "lan":
		on, ok := parseOnOff(pos[2])
		if !ok {
			return fmt.Errorf("lan needs on or off")
		}
		changed = cfg.LAN != on
		cfg.LAN = on
		if on {
			say("The endpoint listens on all network interfaces (0.0.0.0:%d). It still needs the API key, but the traffic is not encrypted: use it on a network you trust.", cfg.port())
		} else {
			say("The endpoint listens on this computer only (127.0.0.1:%d)", cfg.port())
		}
	default:
		return fmt.Errorf("unknown setting %q (idle-minutes, lan)", pos[1])
	}
	if err := saveInferConfig(cfg); err != nil {
		return err
	}
	auditLog(auditEntry{Agent: "inference", Tool: "cli", Capability: "inference.manage", Decision: "config", OK: true, Summary: "set " + pos[1] + " " + pos[2]})
	if o.json {
		emitJSON(map[string]any{"schema": 1, "ok": true, "config": configInfo(cfg)})
	}
	if changed && serviceRunning() {
		return restartService()
	}
	return nil
}

func apiPost(cfg *inferConfig, key, p string, body any, timeout time.Duration) ([]byte, int, error) {
	b, _ := json.Marshal(body)
	req, err := http.NewRequest("POST", cfg.baseURL()+p, bytes.NewReader(b))
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	if key != "" {
		req.Header.Set("Authorization", "Bearer "+key)
	}
	resp, err := (&http.Client{Timeout: timeout}).Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	out, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	return out, resp.StatusCode, err
}

func modelStates(cfg *inferConfig, key string) map[string]string {
	out := map[string]string{}
	b, code, err := apiGet(cfg, key, "/models", 5*time.Second)
	if err != nil || code != 200 {
		return out
	}
	var r struct {
		Data []struct {
			ID     string `json:"id"`
			Status struct {
				Value string `json:"value"`
			} `json:"status"`
		} `json:"data"`
	}
	if json.Unmarshal(b, &r) == nil {
		for _, d := range r.Data {
			out[d.ID] = d.Status.Value
		}
	}
	return out
}

func inMemory(state string) bool {
	return state == "loaded" || state == "loading" || state == "sleeping"
}

func unloadModels(cfg *inferConfig, key string, only string) ([]string, error) {
	states := modelStates(cfg, key)
	var names []string
	for name, st := range states {
		if inMemory(st) && (only == "" || only == name) {
			names = append(names, name)
		}
	}
	if only != "" && len(names) == 0 {
		if _, ok := states[only]; !ok {
			return nil, fmt.Errorf("the server does not know a model %q", only)
		}
	}
	for _, n := range names {
		_, code, err := apiPost(cfg, key, "/models/unload", map[string]string{"model": n}, 20*time.Second)
		if err != nil {
			return nil, err
		}
		if code != 200 {
			return nil, fmt.Errorf("the server refused to unload %s (HTTP %d)", n, code)
		}
	}
	deadline := time.Now().Add(20 * time.Second)
	for time.Now().Before(deadline) {
		left := false
		st := modelStates(cfg, key)
		for _, n := range names {
			if inMemory(st[n]) {
				left = true
			}
		}
		if !left {
			break
		}
		time.Sleep(300 * time.Millisecond)
	}
	return names, nil
}

func cmdInferUnload(o iopts, pos []string) error {
	if len(pos) > 1 {
		return fmt.Errorf("usage: kwick-agents inference unload [ID]")
	}
	cfg := loadInferConfig()
	key, _ := inferKey(false)
	if !healthy(cfg, key) {
		return fmt.Errorf("the inference service is not running")
	}
	only := ""
	if len(pos) == 1 {
		only = strings.ToLower(pos[0])
		if only != inferAlias && !modelIDRe.MatchString(only) {
			return fmt.Errorf("invalid model id %q", only)
		}
		if only == cfg.Model {
			only = inferAlias
		}
	}
	names, err := unloadModels(cfg, key, only)
	if err != nil {
		return err
	}
	if o.json {
		if names == nil {
			names = []string{}
		}
		emitJSON(map[string]any{"schema": 1, "ok": true, "unloaded": names})
		return nil
	}
	if len(names) == 0 {
		say("no model is in memory")
	} else {
		say("unloaded %s; it loads again with the next request", strings.Join(names, ", "))
	}
	return nil
}

type memInfo struct {
	Measured bool   `json:"measured"`
	Source   string `json:"source,omitempty"`
	Kind     string `json:"kind,omitempty"`
	UsedMB   int64  `json:"used_mb"`
	TotalMB  int64  `json:"total_mb"`
	Process  bool   `json:"process"`
}

func descendants(root int) map[int]bool {
	kids := map[int][]int{}
	ents, _ := os.ReadDir("/proc")
	for _, e := range ents {
		pid, err := strconv.Atoi(e.Name())
		if err != nil {
			continue
		}
		b, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", pid))
		if err != nil {
			continue
		}
		s := string(b)
		i := strings.LastIndexByte(s, ')')
		if i < 0 {
			continue
		}
		f := strings.Fields(s[i+1:])
		if len(f) < 2 {
			continue
		}
		pp, _ := strconv.Atoi(f[1])
		kids[pp] = append(kids[pp], pid)
	}
	out := map[int]bool{}
	var walk func(p int)
	walk = func(p int) {
		for _, k := range kids[p] {
			if !out[k] {
				out[k] = true
				walk(k)
			}
		}
	}
	walk(root)
	return out
}

func nvidiaMemory(pids map[int]bool, loaded bool, hw Hardware) *memInfo {
	smi := lookPath("nvidia-smi")
	if smi == "" {
		return nil
	}
	var total int64
	for _, d := range hw.Devices {
		if d.Vendor == "nvidia" {
			total += d.VRAMMB
		}
	}
	out, err := runTimeout(5*time.Second, smi, "--query-compute-apps=pid,used_memory", "--format=csv,noheader,nounits")
	if err != nil {
		return nil
	}
	var used int64
	found := false
	for _, l := range strings.Split(string(out), "\n") {
		f := strings.Split(l, ",")
		if len(f) < 2 {
			continue
		}
		pid, err1 := strconv.Atoi(strings.TrimSpace(f[0]))
		mb, err2 := strconv.ParseInt(strings.TrimSpace(f[1]), 10, 64)
		if err1 == nil && err2 == nil && pids[pid] {
			used += mb
			found = true
		}
	}
	if found || !loaded {
		return &memInfo{Measured: true, Source: "nvidia-smi", Kind: "gpu", UsedMB: used, TotalMB: total, Process: true}
	}
	out, err = runTimeout(5*time.Second, smi, "--query-gpu=memory.used,memory.total", "--format=csv,noheader,nounits")
	if err != nil {
		return nil
	}
	var du, dt int64
	for _, l := range strings.Split(string(out), "\n") {
		f := strings.Split(l, ",")
		if len(f) < 2 {
			continue
		}
		u, e1 := strconv.ParseInt(strings.TrimSpace(f[0]), 10, 64)
		t, e2 := strconv.ParseInt(strings.TrimSpace(f[1]), 10, 64)
		if e1 == nil && e2 == nil {
			du += u
			dt += t
		}
	}
	if dt == 0 {
		return nil
	}
	return &memInfo{Measured: true, Source: "nvidia-smi", Kind: "gpu", UsedMB: du, TotalMB: dt}
}

func fdinfoKiB(line, key string) int64 {
	if !strings.HasPrefix(line, key) {
		return 0
	}
	f := strings.Fields(strings.TrimPrefix(line, key))
	if len(f) == 0 {
		return 0
	}
	n, _ := strconv.ParseInt(f[0], 10, 64)
	if len(f) > 1 && strings.EqualFold(f[1], "MiB") {
		n *= 1024
	}
	return n
}

func amdMemory(pids map[int]bool, loaded bool, hw Hardware) *memInfo {
	var kib int64
	seen := map[string]bool{}
	found := false
	for pid := range pids {
		fds, _ := filepath.Glob(fmt.Sprintf("/proc/%d/fdinfo/*", pid))
		for _, f := range fds {
			b, err := os.ReadFile(f)
			if err != nil || !bytes.Contains(b, []byte("drm-driver:\tamdgpu")) {
				continue
			}
			id := ""
			var n int64
			for _, l := range strings.Split(string(b), "\n") {
				if strings.HasPrefix(l, "drm-client-id:") {
					id = strings.TrimSpace(strings.TrimPrefix(l, "drm-client-id:"))
				}
				n += fdinfoKiB(l, "drm-memory-vram:") + fdinfoKiB(l, "drm-memory-gtt:")
			}
			key := fmt.Sprintf("%d/%s", pid, id)
			if id != "" && seen[key] {
				continue
			}
			seen[key] = true
			kib += n
			found = true
		}
	}
	if found {
		return &memInfo{Measured: true, Source: "amdgpu-fdinfo", Kind: "gpu", UsedMB: kib / 1024, TotalMB: hw.MemoryBudgetMB, Process: true}
	}
	if !loaded {
		return &memInfo{Measured: true, Source: "amdgpu-fdinfo", Kind: "gpu", UsedMB: 0, TotalMB: hw.MemoryBudgetMB, Process: true}
	}
	var used, total int64
	for _, d := range hw.Devices {
		if d.Vendor != "amd" || d.Card == "" {
			continue
		}
		base := filepath.Join("/sys/class/drm", d.Card, "device")
		v, e1 := strconv.ParseInt(readTrim(filepath.Join(base, "mem_info_vram_used")), 10, 64)
		g, _ := strconv.ParseInt(readTrim(filepath.Join(base, "mem_info_gtt_used")), 10, 64)
		if e1 != nil {
			continue
		}
		used += v
		if d.Unified {
			used += g
		}
		total += d.VRAMMB + d.GTTMB
	}
	if total == 0 {
		return nil
	}
	return &memInfo{Measured: true, Source: "amdgpu-sysfs", Kind: "gpu", UsedMB: used >> 20, TotalMB: hw.MemoryBudgetMB}
}

func rssMemory(pids map[int]bool, hw Hardware) *memInfo {
	var kib int64
	for pid := range pids {
		b, err := os.ReadFile(fmt.Sprintf("/proc/%d/status", pid))
		if err != nil {
			continue
		}
		for _, l := range strings.Split(string(b), "\n") {
			if strings.HasPrefix(l, "VmRSS:") {
				f := strings.Fields(l)
				if len(f) >= 2 {
					n, _ := strconv.ParseInt(f[1], 10, 64)
					kib += n
				}
			}
		}
	}
	return &memInfo{Measured: true, Source: "process-rss", Kind: "ram", UsedMB: kib / 1024, TotalMB: hw.RAMMB, Process: true}
}

func measureMemory(root int, loaded bool, hw Hardware, backend string) *memInfo {
	if root <= 0 {
		return nil
	}
	pids := descendants(root)
	switch {
	case backend == "cpu":
		return rssMemory(pids, hw)
	case hw.Accelerator == "nvidia":
		return nvidiaMemory(pids, loaded, hw)
	case hw.Accelerator == "amd":
		return amdMemory(pids, loaded, hw)
	}
	return nil
}

type benchResult struct {
	Schema       int     `json:"schema"`
	OK           bool    `json:"ok"`
	Model        string  `json:"model"`
	Engine       string  `json:"engine,omitempty"`
	Backend      string  `json:"backend,omitempty"`
	Devices      string  `json:"devices,omitempty"`
	PromptTokens int     `json:"prompt_tokens"`
	GenTokens    int     `json:"gen_tokens"`
	PromptTPS    float64 `json:"prompt_tps"`
	GenTPS       float64 `json:"gen_tps"`
	Seconds      float64 `json:"seconds"`
	At           string  `json:"at"`
	Error        string  `json:"error,omitempty"`
}

const (
	benchPrompt = 128
	benchGen    = 32
)

func benchPath() string { return filepath.Join(userScope().State, "inference-bench.json") }

func lastBench() *benchResult {
	var b benchResult
	if readJSONFile(benchPath(), &b) != nil || b.Model == "" || !b.OK {
		return nil
	}
	return &b
}

func round1(f float64) float64 { return float64(int64(f*10+0.5)) / 10 }

func parseBench(out []byte) (prompt, gen float64, pn, gn int, devices string, err error) {
	i := bytes.IndexByte(out, '[')
	if i < 0 {
		return 0, 0, 0, 0, "", fmt.Errorf("llama-bench printed no result")
	}
	var rows []struct {
		NPrompt  int     `json:"n_prompt"`
		NGen     int     `json:"n_gen"`
		AvgTS    float64 `json:"avg_ts"`
		Backends string  `json:"backends"`
		GPUInfo  string  `json:"gpu_info"`
		CPUInfo  string  `json:"cpu_info"`
	}
	dec := json.NewDecoder(bytes.NewReader(out[i:]))
	if err := dec.Decode(&rows); err != nil {
		return 0, 0, 0, 0, "", fmt.Errorf("llama-bench printed an unexpected result: %v", err)
	}
	for _, r := range rows {
		switch {
		case r.NGen == 0 && r.NPrompt > 0:
			prompt, pn = r.AvgTS, r.NPrompt
		case r.NPrompt == 0 && r.NGen > 0:
			gen, gn = r.AvgTS, r.NGen
		}
		if devices == "" {
			devices = strings.TrimSpace(r.GPUInfo)
			if devices == "" {
				devices = strings.TrimSpace(r.CPUInfo)
			}
			if r.Backends != "" {
				devices = r.Backends + ": " + devices
			}
		}
	}
	if prompt == 0 && gen == 0 {
		return 0, 0, 0, 0, "", fmt.Errorf("llama-bench reported no speed")
	}
	return prompt, gen, pn, gn, devices, nil
}

func cmdInferBench(o iopts) error {
	cfg := loadInferConfig()
	st, ok := loadInferState()
	if !ok {
		return fmt.Errorf("the engine is not installed (kwick-agents inference install)")
	}
	bench := filepath.Join(st.Dir, "llama-bench")
	if !exists(bench) {
		return fmt.Errorf("this llama.cpp build has no llama-bench")
	}
	if cfg.Model == "" {
		return fmt.Errorf("no model selected (kwick-agents inference use best)")
	}
	mc, err := loadModelCatalog()
	if err != nil {
		return err
	}
	m, err := mc.find(cfg.Model)
	if err != nil {
		return err
	}
	if inst, _ := installedModel(m); !inst {
		return fmt.Errorf("%s is not downloaded (kwick-agents inference model pull %s)", m.ID, m.ID)
	}
	if key, _ := inferKey(false); healthy(cfg, key) {
		if names, err := unloadModels(cfg, key, ""); err == nil && len(names) > 0 {
			say("unloaded %s to give the benchmark the whole memory; it loads again with the next request", strings.Join(names, ", "))
		}
	}
	say("Benchmarking %s on %s: %d prompt tokens, %d generated tokens", m.ID, st.Backend, benchPrompt, benchGen)
	argv := []string{bench, "-m", modelPath(m), "-p", strconv.Itoa(benchPrompt), "-n", strconv.Itoa(benchGen), "-r", "2", "-o", "json"}
	if n := runtime.GOMAXPROCS(0); n < runtime.NumCPU() {
		argv = append(argv, "-t", strconv.Itoa(n))
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Minute)
	defer cancel()
	base := sandboxCmd(cfg, st.Dir, inferModelsDir(), st.Backend, argv)
	c := exec.CommandContext(ctx, base.Path, base.Args[1:]...)
	c.Env, c.Dir = base.Env, base.Dir
	var stdout, stderr bytes.Buffer
	c.Stdout, c.Stderr = &stdout, &stderr
	t0 := time.Now()
	runErr := c.Run()
	res := benchResult{Schema: 1, Model: m.ID, Engine: st.Build, Backend: st.Backend, PromptTokens: benchPrompt, GenTokens: benchGen, Seconds: round1(time.Since(t0).Seconds()), At: nowStamp()}
	if runErr != nil {
		res.Error = fmt.Sprintf("llama-bench failed: %v: %s", runErr, lastLines(stderr.String(), 4))
	} else if p, g, pn, gn, dev, perr := parseBench(stdout.Bytes()); perr != nil {
		res.Error = perr.Error()
	} else {
		res.OK, res.PromptTPS, res.GenTPS, res.Devices = true, round1(p), round1(g), dev
		if pn > 0 {
			res.PromptTokens = pn
		}
		if gn > 0 {
			res.GenTokens = gn
		}
	}
	if res.OK {
		os.MkdirAll(filepath.Dir(benchPath()), 0o755)
		writeJSONFile(benchPath(), res, 0o644)
	}
	if o.json {
		emitJSON(res)
	} else if res.OK {
		fmt.Printf("Prompt processing: %.1f tokens/s\nGeneration:        %.1f tokens/s\n(%s, %s, %.0f s)\n", res.PromptTPS, res.GenTPS, m.ID, res.Backend, res.Seconds)
	}
	if res.Error != "" {
		if o.json {
			return exitErr{1}
		}
		return fmt.Errorf("%s", res.Error)
	}
	return nil
}
