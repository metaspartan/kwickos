package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

func testModel(t *testing.T, data []byte) *ModelEntry {
	t.Helper()
	sum := sha256.Sum256(data)
	return &ModelEntry{ID: "tiny-test", Title: "t", Repo: "kwick/test", Commit: strings.Repeat("a", 40), Quant: "Q4_K_M",
		Files: []ModelFile{{Name: "tiny.gguf", Size: int64(len(data)), SHA256: hex.EncodeToString(sum[:])}}, License: "mit"}
}

func TestPullTrackerStates(t *testing.T) {
	testEnv(t)
	data := bytes.Repeat([]byte("progress "), 200000)
	m := testModel(t, data)
	var mu sync.Mutex
	var seen []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", strconv.Itoa(len(data)))
		for off := 0; off < len(data); off += 100000 {
			end := off + 100000
			if end > len(data) {
				end = len(data)
			}
			w.Write(data[off:end])
			w.(http.Flusher).Flush()
			time.Sleep(60 * time.Millisecond)
			mu.Lock()
			if d := loadDownload(m.ID); d != nil {
				seen = append(seen, d.State)
			}
			mu.Unlock()
		}
	}))
	defer srv.Close()
	tr := newPullTracker(m)
	dest := filepath.Join(inferModelsDir(), m.ID, "tiny.gguf")
	if err := resumeDownload(srv.URL+"/x", m.Files[0].SHA256, m.Files[0].Size, dest, tr); err != nil {
		t.Fatal(err)
	}
	tr.finishFile(m.Files[0].Size)
	d := loadDownload(m.ID)
	if d == nil || d.Total != int64(len(data)) || d.Done != int64(len(data)) || d.State != "downloading" || d.PID != os.Getpid() {
		t.Fatalf("%+v", d)
	}
	if len(seen) == 0 || seen[0] != "downloading" {
		t.Fatalf("states seen while downloading: %v", seen)
	}
	tr.clear()
	if loadDownload(m.ID) != nil {
		t.Fatal("state kept after a finished pull")
	}
}

func TestPullFailureAndStale(t *testing.T) {
	testEnv(t)
	m := testModel(t, []byte("x"))
	tr := newPullTracker(m)
	tr.fail(http.ErrAbortHandler)
	d := loadDownload(m.ID)
	if d == nil || d.State != "failed" || d.Error == "" {
		t.Fatalf("%+v", d)
	}
	writeJSONFile(pullPath(m.ID), DownloadInfo{State: "downloading", Done: 5, Total: 10, Rate: 7, PID: 999999}, 0o644)
	d = loadDownload(m.ID)
	if d == nil || d.State != "failed" || d.Rate != 0 || !strings.Contains(d.Error, "interrupted") {
		t.Fatalf("a dead pull still looks active: %+v", d)
	}
	if loadDownload("../escape") != nil {
		t.Fatal("path in id")
	}
}

func TestCancelPullKeepsPart(t *testing.T) {
	testEnv(t)
	mc, err := loadModelCatalog()
	if err != nil {
		t.Fatal(err)
	}
	m := mc.Models[0]
	part := filepath.Join(modelDir(m.ID), filepath.FromSlash(m.Files[0].Name)) + ".part"
	os.MkdirAll(filepath.Dir(part), 0o755)
	os.WriteFile(part, make([]byte, 4096), 0o644)
	c := exec.Command("sh", "-c", "sleep 30 # inference pull")
	if err := c.Start(); err != nil {
		t.Fatal(err)
	}
	go c.Wait()
	os.MkdirAll(pullsDir(), 0o755)
	writeJSONFile(pullPath(m.ID), DownloadInfo{State: "downloading", Done: 4096, Total: m.size(), PID: c.Process.Pid}, 0o644)
	if d := loadDownload(m.ID); d == nil || d.State != "downloading" {
		t.Fatalf("%+v", d)
	}
	kept, err := cancelPull(m.ID)
	if err != nil || kept != 4096 {
		t.Fatalf("kept %d, %v", kept, err)
	}
	if loadDownload(m.ID) != nil || pullAlive(c.Process.Pid) || !exists(part) {
		t.Fatal("cancel left the download running or removed the partial file")
	}
	if kept, err := cancelPull(m.ID); err != nil || kept != 0 {
		t.Fatalf("second cancel: %d %v", kept, err)
	}
	if _, err := cancelPull("../x"); err == nil {
		t.Fatal("invalid id accepted")
	}
}

func TestModelItemsCarryDownload(t *testing.T) {
	testEnv(t)
	mc, err := loadModelCatalog()
	if err != nil {
		t.Fatal(err)
	}
	m := mc.Models[0]
	os.MkdirAll(pullsDir(), 0o755)
	writeJSONFile(pullPath(m.ID), DownloadInfo{State: "verifying", Done: m.size(), Total: m.size(), PID: 999999}, 0o644)
	p := filepath.Join(modelDir(m.ID), filepath.FromSlash(m.Files[0].Name)) + ".part"
	os.MkdirAll(filepath.Dir(p), 0o755)
	os.WriteFile(p, make([]byte, 100), 0o644)
	items := modelItems(mc, Hardware{Accelerator: "cpu"}, 0, loadInferConfig(), false)
	b, _ := json.Marshal(items[0])
	var got map[string]any
	json.Unmarshal(b, &got)
	dl, _ := got["download"].(map[string]any)
	if dl == nil || dl["state"] != "failed" || got["partial_bytes"].(float64) != 100 {
		t.Fatalf("%s", b)
	}
	b, _ = json.Marshal(items[1])
	got = map[string]any{}
	json.Unmarshal(b, &got)
	if v, ok := got["download"]; !ok || v != nil {
		t.Fatalf("download must be present and null: %s", b)
	}
}

func TestConfigSet(t *testing.T) {
	testEnv(t)
	run := func(a ...string) error { return cmdInferConfig(iopts{}, a) }
	if err := run("set", "idle-minutes", "5"); err != nil {
		t.Fatal(err)
	}
	if c := loadInferConfig(); c.idle() != 300 {
		t.Fatal(c.idle())
	}
	if err := run("set", "idle-minutes", "never"); err != nil {
		t.Fatal(err)
	}
	c := loadInferConfig()
	if c.idle() != 0 {
		t.Fatal(c.idle())
	}
	hw := Hardware{Accelerator: "cpu"}
	if a := strings.Join(serverArgs(c, "/e", "/r", hw), " "); strings.Contains(a, "sleep-idle") || !strings.Contains(a, "--host 127.0.0.1") {
		t.Fatal(a)
	}
	for _, bad := range []string{"0m", "2000", "-3", "soon"} {
		if err := run("set", "idle-minutes", bad); err == nil {
			t.Fatalf("%s accepted", bad)
		}
	}
	if err := run("set", "lan", "on"); err != nil {
		t.Fatal(err)
	}
	c = loadInferConfig()
	if !c.LAN || c.host() != "0.0.0.0" {
		t.Fatal("lan not persisted")
	}
	if a := strings.Join(serverArgs(c, "/e", "/r", hw), " "); !strings.Contains(a, "--host 0.0.0.0") || !strings.Contains(a, "--api-key-file /r/api-key") {
		t.Fatal(a)
	}
	s := getServiceStatus(c)
	if !s.LAN || s.Host != "0.0.0.0" || s.IdleSeconds != 0 {
		t.Fatalf("%+v", s)
	}
	if err := run("set", "lan", "off"); err != nil || loadInferConfig().LAN {
		t.Fatal("lan not turned off")
	}
	if err := run("set", "lan", "maybe"); err == nil {
		t.Fatal("bad value accepted")
	}
	if err := run("set", "port", "1"); err == nil {
		t.Fatal("unknown setting accepted")
	}
	if err := run("set", "idle-minutes", "15"); err != nil || loadInferConfig().idle() != 900 {
		t.Fatal("idle not back to 15 minutes")
	}
}

func routerServer(t *testing.T, states map[string]string) (*httptest.Server, *inferConfig, *[]string) {
	t.Helper()
	var mu sync.Mutex
	var unloaded []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		switch {
		case r.URL.Path == "/health":
			w.Write([]byte(`{"status":"ok"}`))
		case r.URL.Path == "/models":
			var rows []map[string]any
			for id, st := range states {
				rows = append(rows, map[string]any{"id": id, "status": map[string]any{"value": st}})
			}
			json.NewEncoder(w).Encode(map[string]any{"data": rows})
		case r.URL.Path == "/models/unload" && r.Method == "POST":
			var b map[string]string
			json.NewDecoder(r.Body).Decode(&b)
			if r.Header.Get("Authorization") != "Bearer k" {
				w.WriteHeader(401)
				return
			}
			unloaded = append(unloaded, b["model"])
			states[b["model"]] = "unloaded"
			w.Write([]byte(`{"success":true}`))
		default:
			w.WriteHeader(404)
		}
	}))
	u, _ := url.Parse(srv.URL)
	port, _ := strconv.Atoi(u.Port())
	return srv, &inferConfig{Port: port}, &unloaded
}

func TestUnloadModels(t *testing.T) {
	testEnv(t)
	srv, cfg, unloaded := routerServer(t, map[string]string{"local": "loaded", "qwen3.5-9b": "unloaded", "gemma": "sleeping"})
	defer srv.Close()
	names, err := unloadModels(cfg, "k", "")
	if err != nil || len(names) != 2 || len(*unloaded) != 2 {
		t.Fatalf("%v %v %v", names, *unloaded, err)
	}
	if st := modelStates(cfg, "k"); inMemory(st["local"]) || inMemory(st["gemma"]) {
		t.Fatal(st)
	}
	if names, err := unloadModels(cfg, "k", "local"); err != nil || len(names) != 0 {
		t.Fatalf("%v %v", names, err)
	}
	if _, err := unloadModels(cfg, "k", "nope"); err == nil {
		t.Fatal("unknown model accepted")
	}
}

func TestUnloadRefusedWithWrongKey(t *testing.T) {
	testEnv(t)
	srv, cfg, unloaded := routerServer(t, map[string]string{"local": "loaded"})
	defer srv.Close()
	if _, err := unloadModels(cfg, "wrong", ""); err == nil || len(*unloaded) != 0 {
		t.Fatal("unloaded with the wrong key")
	}
}

func TestParseBench(t *testing.T) {
	out := []byte("build: x\n" + `[{"build_commit":"abc","backends":"CPU","cpu_info":"Some CPU","gpu_info":"","n_prompt":128,"n_gen":0,"avg_ts":412.34,"stddev_ts":1.0},
{"build_commit":"abc","backends":"CPU","cpu_info":"Some CPU","gpu_info":"","n_prompt":0,"n_gen":32,"avg_ts":21.56,"stddev_ts":0.2}]`)
	p, g, pn, gn, dev, err := parseBench(out)
	if err != nil || p != 412.34 || g != 21.56 || pn != 128 || gn != 32 || dev != "CPU: Some CPU" {
		t.Fatal(p, g, pn, gn, dev, err)
	}
	if round1(p) != 412.3 || round1(g) != 21.6 {
		t.Fatal(round1(p), round1(g))
	}
	if _, _, _, _, _, err := parseBench([]byte("no json here")); err == nil {
		t.Fatal("garbage accepted")
	}
	if _, _, _, _, _, err := parseBench([]byte("[]")); err == nil {
		t.Fatal("empty result accepted")
	}
}

func TestHFTokenHandling(t *testing.T) {
	testEnv(t)
	t.Setenv("HF_TOKEN", "")
	if hfTokenSet() || hfToken() != "" {
		t.Fatal("token from nowhere")
	}
	if _, err := secretSet("shared", hfTokenEnv, "hf_secret123"); err != nil {
		t.Fatal(err)
	}
	if !hfTokenSet() || hfToken() != "hf_secret123" {
		t.Fatal("stored token not found")
	}
	req, _ := http.NewRequest("GET", "https://huggingface.co/api/models/x", nil)
	hfAuth(req)
	if req.Header.Get("Authorization") != "Bearer hf_secret123" {
		t.Fatal("no auth for huggingface.co")
	}
	for _, u := range []string{"https://example.com/x", "https://huggingface.co.evil.com/x", "http://127.0.0.1:1/x", "https://cas-bridge.xethub.hf.co/x"} {
		r, _ := http.NewRequest("GET", u, nil)
		hfAuth(r)
		if r.Header.Get("Authorization") != "" {
			t.Fatalf("token sent to %s", u)
		}
	}
	var gotAuth []string
	var mu sync.Mutex
	other := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		gotAuth = append(gotAuth, "other:"+r.Header.Get("Authorization"))
		mu.Unlock()
		w.Write([]byte("ok"))
	}))
	defer other.Close()
	otherURL := strings.Replace(other.URL, "127.0.0.1", "localhost", 1)
	hf := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		gotAuth = append(gotAuth, "hf:"+r.Header.Get("Authorization"))
		mu.Unlock()
		http.Redirect(w, r, otherURL+"/blob", http.StatusFound)
	}))
	defer hf.Close()
	old := hfAPIBase
	hfAPIBase = hf.URL
	defer func() { hfAPIBase = old }()
	req, _ = http.NewRequest("GET", hf.URL+"/file", nil)
	hfAuth(req)
	resp, err := modelHTTP.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	mu.Lock()
	defer mu.Unlock()
	joined := strings.Join(gotAuth, " ")
	if !strings.Contains(joined, "hf:Bearer hf_secret123") || !strings.Contains(joined, "other:") || strings.Contains(joined, "other:Bearer") {
		t.Fatalf("auth sent across hosts: %v", gotAuth)
	}
}

func TestGatedNeedsToken(t *testing.T) {
	testEnv(t)
	t.Setenv("HF_TOKEN", "")
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"id":"a/b","sha":"` + strings.Repeat("c", 40) + `","gated":"manual","siblings":[],"cardData":{"license":"gemma"}}`))
	}))
	defer srv.Close()
	old := hfAPIBase
	hfAPIBase = srv.URL
	defer func() { hfAPIBase = old }()
	_, err := addHFModel("hf://a/b")
	if err == nil || !strings.Contains(err.Error(), "HF_TOKEN") {
		t.Fatal(err)
	}
	t.Setenv("HF_TOKEN", "hf_x")
	_, err = addHFModel("hf://a/b")
	if err == nil || !strings.Contains(err.Error(), "no access") {
		t.Fatal(err)
	}
}

func TestMeasureRSS(t *testing.T) {
	c := exec.Command("sleep", "5")
	if err := c.Start(); err != nil {
		t.Skip("no sleep")
	}
	defer func() { c.Process.Kill(); c.Wait() }()
	pids := descendants(os.Getpid())
	if !pids[c.Process.Pid] {
		t.Fatalf("child %d not found in %v", c.Process.Pid, pids)
	}
	m := rssMemory(map[int]bool{c.Process.Pid: true}, Hardware{RAMMB: 1000})
	if !m.Measured || m.Source != "process-rss" || m.Kind != "ram" || m.TotalMB != 1000 {
		t.Fatalf("%+v", m)
	}
	if measureMemory(0, false, Hardware{}, "cpu") != nil {
		t.Fatal("measured without a service")
	}
}
