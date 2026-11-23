package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type serviceStatus struct {
	Enabled      bool     `json:"enabled"`
	Running      bool     `json:"running"`
	Healthy      bool     `json:"healthy"`
	PID          int      `json:"pid"`
	URL          string   `json:"url"`
	AnthropicURL string   `json:"anthropic_url"`
	Host         string   `json:"host"`
	Port         int      `json:"port"`
	Alias        string   `json:"alias"`
	KeyEnv       string   `json:"key_env"`
	KeySet       bool     `json:"key_set"`
	IdleSeconds  int      `json:"idle_seconds"`
	HeadroomMB   int64    `json:"vram_headroom_mb"`
	Sandbox      bool     `json:"sandbox"`
	Supervisor   string   `json:"supervisor"`
	Loaded       []string `json:"loaded"`
	Log          string   `json:"log"`
}

func pidFile() string { return filepath.Join(inferRunDir(), "pid") }

func readPid() int {
	n, _ := strconv.Atoi(readTrim(pidFile()))
	if n <= 1 {
		return 0
	}
	cl, err := os.ReadFile(fmt.Sprintf("/proc/%d/cmdline", n))
	if err != nil || !strings.Contains(string(cl), "inference\x00service\x00run") {
		return 0
	}
	return n
}

func serviceRunning() bool { return readPid() > 0 }

func autostartPath() string {
	return filepath.Join(xdg("XDG_CONFIG_HOME", ".config"), "autostart", "kwick-inference.desktop")
}

func serviceEnabled(cfg *inferConfig) bool {
	if inferSystem {
		out, err := exec.Command("systemctl", "is-enabled", "kwick-inference.service").Output()
		return err == nil && strings.TrimSpace(string(out)) == "enabled"
	}
	return exists(autostartPath())
}

func maxHeadroom(hw Hardware) int64 {
	var h int64 = 512
	for _, d := range hw.Devices {
		if d.Vendor == hw.Accelerator && displayHeadroomMB(d) > h {
			h = displayHeadroomMB(d)
		}
	}
	return h
}

func getServiceStatus(cfg *inferConfig) serviceStatus {
	s := serviceStatus{URL: cfg.baseURL() + "/v1", AnthropicURL: cfg.baseURL(), Host: "127.0.0.1", Port: cfg.port(), Alias: inferAlias,
		KeyEnv: inferKeyEnv, KeySet: keyStored(), IdleSeconds: cfg.idle(), Sandbox: cfg.sandbox(), Loaded: []string{}, Log: inferLogPath()}
	s.Enabled = serviceEnabled(cfg)
	s.Supervisor = "kwick-agents"
	if inferSystem {
		s.Supervisor = "kinit"
	}
	s.HeadroomMB = maxHeadroom(detectHardware())
	s.PID = readPid()
	s.Running = s.PID > 0
	if s.Running || inferSystem {
		key, _ := inferKey(false)
		if healthy(cfg, key) {
			s.Healthy = true
			s.Running = true
			s.Loaded = loadedModels(cfg, key)
		}
	}
	return s
}

func apiGet(cfg *inferConfig, key, p string, timeout time.Duration) ([]byte, int, error) {
	req, err := http.NewRequest("GET", cfg.baseURL()+p, nil)
	if err != nil {
		return nil, 0, err
	}
	if key != "" {
		req.Header.Set("Authorization", "Bearer "+key)
	}
	c := &http.Client{Timeout: timeout}
	resp, err := c.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	return b, resp.StatusCode, err
}

func healthy(cfg *inferConfig, key string) bool {
	_, code, err := apiGet(cfg, key, "/health", 3*time.Second)
	return err == nil && code == 200
}

func loadedModels(cfg *inferConfig, key string) []string {
	b, code, err := apiGet(cfg, key, "/models", 5*time.Second)
	out := []string{}
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
			if d.Status.Value == "loaded" || d.Status.Value == "loading" {
				out = append(out, d.ID)
			}
		}
	}
	return out
}

func portBusy(port int) bool {
	c, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), 500*time.Millisecond)
	if err != nil {
		return false
	}
	c.Close()
	return true
}

func iniQuote(s string) string {
	if strings.ContainsAny(s, ";#\n\r=") {
		return strconv.Quote(s)
	}
	return s
}

func presetText(cfg *inferConfig, mc *ModelCatalog, hw Hardware, root string) (string, error) {
	var b strings.Builder
	b.WriteString("version = 1\n\n[*]\n")
	fmt.Fprintf(&b, "c = %d\n", cfg.ctx())
	b.WriteString("jinja = true\n")
	b.WriteString("fit = on\n")
	fmt.Fprintf(&b, "fit-target = %d\n", maxHeadroom(hw))
	fmt.Fprintf(&b, "fit-ctx = %d\n", 4096)
	b.WriteString("load-on-startup = false\n")
	if p := runtime.GOMAXPROCS(0); p < runtime.NumCPU() {
		fmt.Fprintf(&b, "threads = %d\n", p)
	}
	section := func(name string, m *ModelEntry) {
		fmt.Fprintf(&b, "\n[%s]\n", name)
		fmt.Fprintf(&b, "model = %s\n", iniQuote(filepath.Join(root, m.ID, filepath.FromSlash(m.Files[0].Name))))
		if sh, err := modelShape(m); err == nil && sh.ContextMax > 0 && int64(cfg.ctx()) > sh.ContextMax {
			fmt.Fprintf(&b, "c = %d\n", sh.ContextMax)
		}
	}
	var ids []string
	byID := map[string]*ModelEntry{}
	for _, m := range mc.Models {
		if inst, _ := installedModel(m); inst {
			ids = append(ids, m.ID)
			byID[m.ID] = m
		}
	}
	sort.Strings(ids)
	if cur, ok := byID[cfg.Model]; ok {
		section(inferAlias, cur)
	} else if cfg.Model != "" {
		return "", fmt.Errorf("the selected model %s is not downloaded (kwick-agents inference model pull %s)", cfg.Model, cfg.Model)
	}
	for _, id := range ids {
		section(id, byID[id])
	}
	return b.String(), nil
}

func writePreset(cfg *inferConfig) error {
	mc, err := loadModelCatalog()
	if err != nil {
		return err
	}
	txt, err := presetText(cfg, mc, detectHardware(), inferModelsDir())
	if err != nil {
		return err
	}
	if err := os.MkdirAll(inferRunDir(), 0o700); err != nil {
		return err
	}
	return writeFileAtomic(filepath.Join(inferRunDir(), "models.ini"), []byte(txt), 0o600)
}

func serverArgs(cfg *inferConfig, engine, run string, hw Hardware) []string {
	return []string{filepath.Join(engine, "llama-server"),
		"--host", "127.0.0.1", "--port", strconv.Itoa(cfg.port()),
		"--api-key-file", filepath.Join(run, "api-key"),
		"--models-preset", filepath.Join(run, "models.ini"),
		"--models-max", "1",
		"--models-memory-margin", strconv.FormatInt(maxHeadroom(hw), 10),
		"--sleep-idle-seconds", strconv.Itoa(cfg.idle()),
		"--no-webui",
	}
}

func sandboxEnv() []string {
	return []string{"PATH=/usr/bin:/bin", "HOME=/tmp", "LANG=C.UTF-8", "TMPDIR=/tmp", "LLAMA_CACHE=/tmp/llama-cache", "LLAMA_LOG_COLORS=off"}
}

func sandboxCmd(cfg *inferConfig, engine, models, backend string, argv []string) *exec.Cmd {
	bw := lookPath("bwrap")
	if !cfg.sandbox() || bw == "" {
		c := exec.Command(argv[0], argv[1:]...)
		c.Env = sandboxEnv()
		c.Dir = "/"
		return c
	}
	c := exec.Command(bw, append(inferBwrapArgs(engine, models, inferRunDir(), backend), argv...)...)
	c.Env = sandboxEnv()
	return c
}

func inferBwrapArgs(engine, models, run, backend string) []string {
	a := []string{"--die-with-parent", "--unshare-all", "--share-net", "--new-session", "--ro-bind", "/usr", "/usr"}
	for _, d := range []string{"/bin", "/sbin", "/lib", "/lib64", "/lib32", "/libx32"} {
		fi, err := os.Lstat(d)
		if err != nil {
			continue
		}
		if fi.Mode()&os.ModeSymlink != 0 {
			t, _ := os.Readlink(d)
			a = append(a, "--symlink", t, d)
		} else if fi.IsDir() {
			a = append(a, "--ro-bind", d, d)
		}
	}
	a = append(a, "--ro-bind", "/etc", "/etc", "--ro-bind-try", "/sys", "/sys", "--proc", "/proc", "--dev", "/dev",
		"--tmpfs", "/tmp", "--tmpfs", "/home", "--tmpfs", "/run", "--dir", "/var", "--tmpfs", "/var/tmp", "--tmpfs", "/root")
	for _, d := range gpuDeviceNodes(backend) {
		a = append(a, "--dev-bind", d, d)
	}
	a = append(a, "--ro-bind", engine, engine)
	if models != "" {
		a = append(a, "--ro-bind", models, models)
	}
	if run != "" && exists(run) {
		a = append(a, "--ro-bind", run, run)
	}
	return append(a, "--chdir", "/tmp", "--")
}

func rotateLog(p string) {
	if st, err := os.Stat(p); err == nil && st.Size() > 5<<20 {
		os.Rename(p, p+".1")
	}
}

func cmdInferService(o iopts, pos []string) int {
	sub := "status"
	if len(pos) > 0 {
		sub = pos[0]
	}
	var err error
	cfg := loadInferConfig()
	switch sub {
	case "run":
		return serviceRun(cfg)
	case "start":
		err = startService(cfg, o)
	case "stop":
		err = stopService()
	case "restart":
		err = restartService()
	case "enable":
		err = enableService(cfg, o, true)
	case "disable":
		err = enableService(cfg, o, false)
	case "status":
		s := getServiceStatus(cfg)
		if o.json {
			emitJSON(map[string]any{"schema": 1, "service": s})
		} else {
			st := "stopped"
			if s.Running {
				st = fmt.Sprintf("running (pid %d)", s.PID)
				if s.Healthy {
					st += ", healthy"
				}
			}
			fmt.Printf("%s on %s; enabled: %v; loaded: %s\n", st, s.URL, s.Enabled, strings.Join(s.Loaded, ", "))
		}
	case "logs", "log":
		if inferSystem {
			args := []string{"-u", "kwick-inference", "-n", strconv.Itoa(o.n)}
			if o.follow {
				args = append(args, "-f")
			}
			c := exec.Command("journalctl", args...)
			c.Stdout, c.Stderr = os.Stdout, os.Stderr
			err = c.Run()
			break
		}
		if !exists(inferLogPath()) {
			fmt.Println("-- no log yet --")
			return 0
		}
		args := []string{"-n", strconv.Itoa(o.n), inferLogPath()}
		if o.follow {
			args = append([]string{"-f"}, args...)
		}
		c := exec.Command("tail", args...)
		c.Stdout, c.Stderr = os.Stdout, os.Stderr
		err = c.Run()
	default:
		warnf("usage: kwick-agents inference service enable|disable|start|stop|restart|status|logs [-n N] [-f]")
		return 2
	}
	if err != nil {
		warnf("%v", err)
		return 1
	}
	return 0
}

func prepareRun(cfg *inferConfig) (*inferState, error) {
	st, ok := loadInferState()
	if !ok {
		return nil, fmt.Errorf("the engine is not installed (kwick-agents inference install)")
	}
	if cfg.Model == "" {
		return nil, fmt.Errorf("no model selected (kwick-agents inference use best, or use ID)")
	}
	if err := os.MkdirAll(inferRunDir(), 0o700); err != nil {
		return nil, err
	}
	os.Chmod(inferRunDir(), 0o700)
	key, err := inferKey(true)
	if err != nil {
		return nil, err
	}
	if err := writeFileAtomic(filepath.Join(inferRunDir(), "api-key"), []byte(key+"\n"), 0o600); err != nil {
		return nil, err
	}
	if err := writePreset(cfg); err != nil {
		return nil, err
	}
	os.MkdirAll(inferModelsDir(), 0o755)
	if err := writeEndpoint(cfg); err != nil {
		warnf("cannot write %s: %v", endpointPath(), err)
	}
	return st, nil
}

func serviceRun(cfg *inferConfig) int {
	if p := readPid(); p > 0 && p != os.Getpid() {
		warnf("the inference service already runs (pid %d)", p)
		return 1
	}
	st, err := prepareRun(cfg)
	if err != nil {
		warnf("%v", err)
		return 1
	}
	if err := writeFileAtomic(pidFile(), []byte(strconv.Itoa(os.Getpid())+"\n"), 0o600); err != nil {
		warnf("%v", err)
		return 1
	}
	defer os.Remove(pidFile())
	if !cfg.sandbox() {
		warnf("llama-server runs WITHOUT the bubblewrap sandbox")
	} else if lookPath("bwrap") == "" {
		warnf("bubblewrap is not installed; llama-server runs without a sandbox")
	}
	sig := make(chan os.Signal, 2)
	signal.Notify(sig, syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP)
	hw := detectHardware()
	var fails []time.Time
	for {
		argv := serverArgs(cfg, st.Dir, inferRunDir(), hw)
		c := sandboxCmd(cfg, st.Dir, inferModelsDir(), st.Backend, argv)
		c.Stdout, c.Stderr = os.Stdout, os.Stderr
		fmt.Fprintf(os.Stderr, "%s kwick-inference: starting llama.cpp %s (%s) on 127.0.0.1:%d, model %s as %q\n", nowStamp(), st.Build, st.Backend, cfg.port(), cfg.Model, inferAlias)
		if err := c.Start(); err != nil {
			warnf("cannot start llama-server: %v", err)
			return 1
		}
		done := make(chan error, 1)
		go func() { done <- c.Wait() }()
		select {
		case s := <-sig:
			c.Process.Signal(syscall.SIGTERM)
			select {
			case <-done:
			case <-time.After(10 * time.Second):
				c.Process.Kill()
				<-done
			}
			if s == syscall.SIGHUP {
				cfg = loadInferConfig()
				if st2, err := prepareRun(cfg); err == nil {
					st = st2
				}
				continue
			}
			fmt.Fprintf(os.Stderr, "%s kwick-inference: stopped\n", nowStamp())
			return 0
		case err := <-done:
			now := time.Now()
			fails = append(fails, now)
			var recent []time.Time
			for _, t := range fails {
				if now.Sub(t) < 2*time.Minute {
					recent = append(recent, t)
				}
			}
			fails = recent
			fmt.Fprintf(os.Stderr, "%s kwick-inference: llama-server exited (%v)\n", nowStamp(), err)
			if len(fails) >= 5 {
				fmt.Fprintf(os.Stderr, "%s kwick-inference: crashed 5 times in 2 minutes; giving up\n", nowStamp())
				return 1
			}
			wait := time.Duration(1<<uint(len(fails))) * time.Second
			select {
			case <-sig:
				return 0
			case <-time.After(wait):
			}
		}
	}
}

func selfExe() string {
	if p, err := os.Executable(); err == nil {
		return p
	}
	return selfPath
}

func startService(cfg *inferConfig, o iopts) error {
	if inferSystem {
		return runSystemctl("start")
	}
	if p := readPid(); p > 0 {
		say("the inference service already runs (pid %d) on %s/v1", p, cfg.baseURL())
		return nil
	}
	if portBusy(cfg.port()) {
		return fmt.Errorf("port %d is already in use by another program", cfg.port())
	}
	if o.noSandbox {
		f := false
		cfg.Sandbox = &f
		saveInferConfig(cfg)
	}
	if _, err := prepareRun(cfg); err != nil {
		return err
	}
	os.MkdirAll(filepath.Dir(inferLogPath()), 0o755)
	rotateLog(inferLogPath())
	lf, err := os.OpenFile(inferLogPath(), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return err
	}
	defer lf.Close()
	devnull, _ := os.Open(os.DevNull)
	c := exec.Command(selfExe(), "inference", "service", "run")
	c.Stdin, c.Stdout, c.Stderr = devnull, lf, lf
	c.Env = os.Environ()
	c.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := c.Start(); err != nil {
		return err
	}
	c.Process.Release()
	key, _ := inferKey(false)
	deadline := time.Now().Add(60 * time.Second)
	for time.Now().Before(deadline) {
		if healthy(cfg, key) {
			say("Local endpoint running: %s/v1 (Anthropic: %s/v1/messages), model %q = %s", cfg.baseURL(), cfg.baseURL(), inferAlias, cfg.Model)
			say("The key is in $%s for agents started by kwick-agents; %s describes the endpoint", inferKeyEnv, shortPath(endpointPath()))
			auditLog(auditEntry{Agent: "inference", Tool: "cli", Capability: "inference.manage", Decision: "start", OK: true, Summary: "service started with " + cfg.Model})
			return nil
		}
		if readPid() == 0 && time.Since(deadline.Add(-60*time.Second)) > 3*time.Second {
			break
		}
		time.Sleep(300 * time.Millisecond)
	}
	return fmt.Errorf("the service did not come up; see: kwick-agents inference service logs")
}

func stopService() error {
	if inferSystem {
		return runSystemctl("stop")
	}
	p := readPid()
	if p == 0 {
		say("the inference service is not running")
		return nil
	}
	syscall.Kill(p, syscall.SIGTERM)
	for i := 0; i < 150; i++ {
		if readPid() == 0 {
			say("inference service stopped")
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}
	syscall.Kill(p, syscall.SIGKILL)
	os.Remove(pidFile())
	return nil
}

func restartService() error {
	if inferSystem {
		return runSystemctl("restart")
	}
	cfg := loadInferConfig()
	if p := readPid(); p > 0 {
		if _, err := prepareRun(cfg); err != nil {
			return err
		}
		syscall.Kill(p, syscall.SIGHUP)
		key, _ := inferKey(false)
		time.Sleep(500 * time.Millisecond)
		for i := 0; i < 100; i++ {
			if healthy(cfg, key) {
				say("inference service restarted with %s", cfg.Model)
				return nil
			}
			time.Sleep(300 * time.Millisecond)
		}
		return fmt.Errorf("the service did not come back; see: kwick-agents inference service logs")
	}
	return startService(cfg, iopts{})
}

func runSystemctl(verb string, extra ...string) error {
	if !isRoot() {
		return reexecRoot(append([]string{"inference"}, inferRawArgs...))
	}
	c := exec.Command("systemctl", append(append([]string{verb}, extra...), "kwick-inference.service")...)
	c.Stdout, c.Stderr = os.Stdout, os.Stderr
	return c.Run()
}

const autostartText = `[Desktop Entry]
Type=Application
Name=KwickOS local models
Comment=Starts the local inference endpoint (kwick-agents inference service enable)
Exec=/usr/bin/kwick-agents inference service start
NoDisplay=true
X-KDE-autostart-phase=2
X-GNOME-Autostart-enabled=true
`

func enableService(cfg *inferConfig, o iopts, on bool) error {
	if inferSystem {
		if on {
			if _, err := prepareRun(cfg); err != nil {
				return err
			}
			return runSystemctl("enable", "--now")
		}
		return runSystemctl("disable", "--now")
	}
	cfg.Enabled = on
	if err := saveInferConfig(cfg); err != nil {
		return err
	}
	if on {
		if err := writeFileAtomic(autostartPath(), []byte(autostartText), 0o644); err != nil {
			return err
		}
		say("The local endpoint now starts at login (%s)", shortPath(autostartPath()))
		return startService(cfg, o)
	}
	os.Remove(autostartPath())
	say("The local endpoint no longer starts at login")
	return stopService()
}
