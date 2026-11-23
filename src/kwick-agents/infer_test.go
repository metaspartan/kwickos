package main

import (
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"testing"
)

const repoRoot = "../.."

func catalogFile() string {
	return filepath.Join(repoRoot, "desktop/agents/rootfs/usr/lib/kwick/agents/catalog.json")
}

func modelsFile() string {
	return filepath.Join(repoRoot, "desktop/agents/rootfs/usr/lib/kwick/agents/inference-models.json")
}

func testEnv(t *testing.T) string {
	t.Helper()
	h := t.TempDir()
	t.Setenv("HOME", h)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(h, ".config"))
	t.Setenv("XDG_DATA_HOME", filepath.Join(h, ".local/share"))
	t.Setenv("XDG_STATE_HOME", filepath.Join(h, ".local/state"))
	t.Setenv("XDG_RUNTIME_DIR", "")
	t.Setenv("KWICK_AGENTS_KEYSTORE", "file")
	t.Setenv("KWICK_AGENTS_CATALOG", catalogFile())
	t.Setenv("KWICK_INFERENCE_MODELS", modelsFile())
	t.Setenv("KWICK_INFERENCE_MODELS_DIR", "")
	t.Setenv("KWICK_INFERENCE_BACKEND", "")
	t.Setenv("CYBARA_API", "")
	t.Setenv("CYBARA_API_KEY", "")
	inferSystem = false
	localRun = false
	return h
}

func TestCatalogInferenceEntry(t *testing.T) {
	testEnv(t)
	c, err := loadCatalog()
	if err != nil {
		t.Fatal(err)
	}
	if c.Entries[0].Name != "cybara" {
		t.Fatalf("first catalog entry is %s, want cybara", c.Entries[0].Name)
	}
	e, err := inferEntry(c)
	if err != nil {
		t.Fatal(err)
	}
	if e.Method != "inference" || !strings.HasPrefix(e.Version, "b") {
		t.Fatalf("method %q version %q", e.Method, e.Version)
	}
	want := map[string][]string{"cpu": {"amd64", "arm64"}, "vulkan": {"amd64", "arm64"}, "cuda12": {"amd64"}, "cuda13": {"amd64", "arm64"}, "rocm": {"amd64"}}
	for b, arches := range want {
		for _, a := range arches {
			ba, ok := e.Backends[b][a]
			if !ok {
				t.Fatalf("no %s build for %s", b, a)
			}
			if !sha256Re.MatchString(ba.SHA256) || ba.Size <= 0 || ba.Format != "tar.gz" || ba.Strip != 1 {
				t.Fatalf("%s/%s not pinned: %+v", b, a, ba)
			}
			if !strings.Contains(ba.URL, "/"+e.Version+"/") {
				t.Fatalf("%s/%s URL %s is not build %s", b, a, ba.URL, e.Version)
			}
			cuda := strings.HasPrefix(b, "cuda")
			if cuda != (ba.Runtime != nil) {
				t.Fatalf("%s/%s runtime pack: %v", b, a, ba.Runtime)
			}
			if ba.Runtime != nil && (!sha256Re.MatchString(ba.Runtime.SHA256) || !strings.Contains(ba.Runtime.URL, "cudart-llama-"+e.Version)) {
				t.Fatalf("%s/%s runtime not pinned: %+v", b, a, ba.Runtime)
			}
		}
	}
	if ok, _ := c.supported(e, "riscv64"); ok {
		t.Fatal("riscv64 must be unsupported")
	}
	if ok, why := c.supported(e, "amd64"); !ok {
		t.Fatal(why)
	}
	var raw map[string]any
	b, _ := os.ReadFile(catalogFile())
	json.Unmarshal(b, &raw)
	for _, x := range raw["entries"].([]any) {
		if x.(map[string]any)["name"] == "inference" && x.(map[string]any)["backends"] == nil {
			t.Fatal("backends lost in the raw catalog")
		}
	}
}

func TestModelCatalog(t *testing.T) {
	testEnv(t)
	mc, err := loadModelCatalog()
	if err != nil {
		t.Fatal(err)
	}
	if n := len(mc.Models); n < 10 || n > 15 {
		t.Fatalf("%d curated models, want 10-15", n)
	}
	classes := map[string]bool{}
	for _, m := range mc.Models {
		classes[m.Class] = true
		if m.Shape == nil || m.Shape.Arch == "" || m.Shape.Layers == 0 || m.Shape.WeightsB <= 0 {
			t.Fatalf("%s has no shape", m.ID)
		}
		if m.License == "" || m.LicenseURL == "" || m.Rank == 0 {
			t.Fatalf("%s: licence or rank missing", m.ID)
		}
		if m.Source != "catalog" {
			t.Fatalf("%s source %s", m.ID, m.Source)
		}
		if d := m.size() - m.Shape.WeightsB; d < 0 || d > 64<<20 {
			t.Fatalf("%s: weights %d vs files %d", m.ID, m.Shape.WeightsB, m.size())
		}
		if !strings.HasPrefix(m.fileURL(m.Files[0]), "https://huggingface.co/"+m.Repo+"/resolve/"+m.Commit+"/") {
			t.Fatalf("%s url %s", m.ID, m.fileURL(m.Files[0]))
		}
	}
	for _, c := range []string{"tiny", "4gb", "8gb", "16gb", "24gb", "64gb", "128gb"} {
		if !classes[c] {
			t.Fatalf("no model in class %s", c)
		}
	}
	bad := []string{
		`{"models":[{"id":"x","repo":"a/b","commit":"0000000000000000000000000000000000000000","files":[{"name":"../x.gguf","size":1,"sha256":"` + strings.Repeat("a", 64) + `"}]}]}`,
		`{"models":[{"id":"x","repo":"a/b","commit":"main","files":[{"name":"x.gguf","size":1,"sha256":"` + strings.Repeat("a", 64) + `"}]}]}`,
		`{"models":[{"id":"X Y","repo":"a/b","commit":"0000000000000000000000000000000000000000","files":[{"name":"x.gguf","size":1,"sha256":"` + strings.Repeat("a", 64) + `"}]}]}`,
		`{"models":[{"id":"x","repo":"a/b","commit":"0000000000000000000000000000000000000000","files":[{"name":"x.gguf","size":1,"sha256":"abc"}]}]}`,
	}
	for _, s := range bad {
		if _, err := parseModelCatalog([]byte(s)); err == nil {
			t.Fatalf("accepted %s", s)
		}
	}
}

func nv(drv, cuda string) GPUDevice {
	return GPUDevice{Vendor: "nvidia", Name: "GeForce", VRAMMB: 24564, Driver: "nvidia", DriverVersion: drv, CUDAVersion: cuda, ComputeCap: "8.9", Display: true}
}

func TestSelectBackend(t *testing.T) {
	testEnv(t)
	c, err := loadCatalog()
	if err != nil {
		t.Fatal(err)
	}
	e, _ := inferEntry(c)
	cases := []struct {
		name     string
		arch     string
		devs     []GPUDevice
		icd      bool
		override string
		want     string
		err      bool
	}{
		{"no gpu", "amd64", nil, true, "", "cpu", false},
		{"nvidia 590 cuda 13", "amd64", []GPUDevice{nv("590.44.01", "13.1")}, true, "", "cuda13", false},
		{"nvidia 575 cuda 12.9", "amd64", []GPUDevice{nv("575.64", "12.9")}, true, "", "cuda12", false},
		{"nvidia 580 no smi cuda", "amd64", []GPUDevice{nv("580.95", "")}, true, "", "cuda13", false},
		{"nvidia 535", "amd64", []GPUDevice{nv("535.247", "12.2")}, true, "", "cuda12", false},
		{"nvidia 470", "amd64", []GPUDevice{nv("470.256", "11.4")}, true, "", "vulkan", false},
		{"nvidia arm64 575", "arm64", []GPUDevice{nv("575.64", "12.9")}, true, "", "vulkan", false},
		{"nvidia arm64 gb10", "arm64", []GPUDevice{{Vendor: "nvidia", Driver: "nvidia", DriverVersion: "580.95", CUDAVersion: "13.0", Unified: true}}, true, "", "cuda13", false},
		{"nouveau", "amd64", []GPUDevice{{Vendor: "nvidia", Driver: "nouveau", VRAMMB: 0}}, true, "", "vulkan", false},
		{"amd", "amd64", []GPUDevice{{Vendor: "amd", Driver: "amdgpu", VRAMMB: 16368, GTTMB: 32000}}, true, "", "vulkan", false},
		{"amd without vulkan", "amd64", []GPUDevice{{Vendor: "amd", Driver: "amdgpu", VRAMMB: 16368}}, false, "", "cpu", false},
		{"intel arc", "amd64", []GPUDevice{{Vendor: "intel", Driver: "xe", VRAMMB: 12288}}, true, "", "vulkan", false},
		{"apple", "arm64", []GPUDevice{{Vendor: "apple", Driver: "asahi", Unified: true}}, true, "", "cpu", false},
		{"override rocm", "amd64", []GPUDevice{{Vendor: "amd", Driver: "amdgpu", VRAMMB: 16368}}, true, "rocm", "rocm", false},
		{"override rocm arm64", "arm64", nil, true, "rocm", "", true},
		{"override bogus", "amd64", nil, true, "metal", "", true},
		{"riscv64", "riscv64", nil, true, "", "", true},
	}
	for _, tc := range cases {
		hw := buildHardware(tc.devs, 65536, tc.arch)
		ch, err := selectBackend(e, hw, tc.override, tc.icd)
		if tc.err {
			if err == nil {
				t.Errorf("%s: want an error, got %s", tc.name, ch.Backend)
			}
			continue
		}
		if err != nil || ch.Backend != tc.want {
			t.Errorf("%s: got %s (%s) %v, want %s", tc.name, ch.Backend, ch.Reason, err, tc.want)
		}
	}
}

func TestBuildHardware(t *testing.T) {
	cases := []struct {
		name    string
		devs    []GPUDevice
		ram     int64
		budget  int64
		acc     string
		unified bool
	}{
		{"cpu 16 GB", nil, 16000, 13952, "cpu", false},
		{"cpu 8 GB", nil, 8000, 5952, "cpu", false},
		{"4090 display", []GPUDevice{nv("590", "13.1")}, 65536, 24564 - 1536, "nvidia", false},
		{"two 3090 headless", []GPUDevice{{Vendor: "nvidia", Driver: "nvidia", DriverVersion: "580", VRAMMB: 24576}, {Vendor: "nvidia", Driver: "nvidia", DriverVersion: "580", VRAMMB: 24576}}, 131072, 2 * (24576 - 512), "nvidia", false},
		{"strix halo", []GPUDevice{{Vendor: "amd", Driver: "amdgpu", VRAMMB: 512, GTTMB: 98304, Unified: true}}, 131072, 98304 + 512, "amd", true},
		{"apple", []GPUDevice{{Vendor: "apple", Driver: "asahi", Unified: true}}, 32768, 28672, "apple", true},
		{"gb10", []GPUDevice{{Vendor: "nvidia", Driver: "nvidia", DriverVersion: "580", Unified: true}}, 131072, 114688, "nvidia", true},
		{"vm only", []GPUDevice{{Vendor: "vm", Driver: "virtio-pci"}}, 16000, 13952, "cpu", false},
		{"nouveau only", []GPUDevice{{Vendor: "nvidia", Driver: "nouveau"}}, 16000, 13952, "cpu", false},
	}
	for _, tc := range cases {
		hw := buildHardware(tc.devs, tc.ram, "amd64")
		if hw.MemoryBudgetMB != tc.budget || hw.Accelerator != tc.acc || hw.Unified != tc.unified {
			t.Errorf("%s: budget %d acc %s unified %v, want %d %s %v", tc.name, hw.MemoryBudgetMB, hw.Accelerator, hw.Unified, tc.budget, tc.acc, tc.unified)
		}
	}
}

func TestDetectGPUsSysfs(t *testing.T) {
	root := t.TempDir()
	mk := func(p, v string) {
		os.MkdirAll(filepath.Dir(filepath.Join(root, p)), 0o755)
		os.WriteFile(filepath.Join(root, p), []byte(v+"\n"), 0o644)
	}
	dev := filepath.Join(root, "sys/devices/pci0000:00/0000:03:00.0")
	os.MkdirAll(dev, 0o755)
	os.MkdirAll(filepath.Join(root, "sys/class/drm/card1"), 0o755)
	os.Symlink(dev, filepath.Join(root, "sys/class/drm/card1/device"))
	os.MkdirAll(filepath.Join(root, "sys/bus/pci/drivers/amdgpu"), 0o755)
	os.Symlink(filepath.Join(root, "sys/bus/pci/drivers/amdgpu"), filepath.Join(dev, "driver"))
	mk("sys/devices/pci0000:00/0000:03:00.0/vendor", "0x1002")
	mk("sys/devices/pci0000:00/0000:03:00.0/device", "0x744c")
	mk("sys/devices/pci0000:00/0000:03:00.0/mem_info_vram_total", strconv.FormatInt(24560<<20, 10))
	mk("sys/devices/pci0000:00/0000:03:00.0/mem_info_gtt_total", strconv.FormatInt(32000<<20, 10))
	mk("sys/devices/pci0000:00/0000:03:00.0/mem_info_vram_vendor", "samsung")
	mk("sys/class/drm/card1-DP-1/status", "connected")
	mk("proc/meminfo", "MemTotal:       65536000 kB")
	mk("usr/share/misc/pci.ids", "1002  Advanced Micro Devices, Inc. [AMD/ATI]\n\t744c  Navi 31 [Radeon RX 7900 XT/7900 XTX]")
	sysRoot = root
	defer func() { sysRoot = "" }()
	devs := detectGPUs()
	if len(devs) != 1 {
		t.Fatalf("got %d devices", len(devs))
	}
	d := devs[0]
	if d.Vendor != "amd" || d.VRAMMB != 24560 || d.GTTMB != 32000 || d.Unified || !d.Display || d.Driver != "amdgpu" || !strings.Contains(d.Name, "Navi 31") || d.PCI != "0000:03:00.0" {
		t.Fatalf("%+v", d)
	}
	if memTotalMB() != 64000 {
		t.Fatalf("ram %d", memTotalMB())
	}
}

func putStr(w io.Writer, s string) {
	binary.Write(w, binary.LittleEndian, uint64(len(s)))
	io.WriteString(w, s)
}

func putValue(w io.Writer, v any) {
	le := binary.LittleEndian
	switch x := v.(type) {
	case string:
		binary.Write(w, le, uint32(8))
		putStr(w, x)
	case bool:
		binary.Write(w, le, uint32(7))
		b := byte(0)
		if x {
			b = 1
		}
		w.Write([]byte{b})
	case int64:
		binary.Write(w, le, uint32(11))
		binary.Write(w, le, x)
	case float64:
		binary.Write(w, le, uint32(12))
		binary.Write(w, le, x)
	case []any:
		binary.Write(w, le, uint32(9))
		et := uint32(11)
		if len(x) > 0 {
			switch x[0].(type) {
			case bool:
				et = 7
			case float64:
				et = 12
			}
		}
		binary.Write(w, le, et)
		binary.Write(w, le, uint64(len(x)))
		for _, e := range x {
			switch y := e.(type) {
			case bool:
				b := byte(0)
				if y {
					b = 1
				}
				w.Write([]byte{b})
			case float64:
				binary.Write(w, le, y)
			case int64:
				binary.Write(w, le, y)
			}
		}
	}
}

func writeGGUFHeader(g *ggufFile) []byte {
	var b bytes.Buffer
	le := binary.LittleEndian
	b.WriteString("GGUF")
	binary.Write(&b, le, uint32(3))
	binary.Write(&b, le, uint64(len(g.Tensors)))
	keys := make([]string, 0, len(g.KV))
	for k := range g.KV {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	binary.Write(&b, le, uint64(len(keys)))
	for _, k := range keys {
		putStr(&b, k)
		putValue(&b, g.KV[k])
	}
	for _, t := range g.Tensors {
		putStr(&b, t.Name)
		binary.Write(&b, le, uint32(len(t.Dims)))
		for _, d := range t.Dims {
			binary.Write(&b, le, d)
		}
		binary.Write(&b, le, t.Type)
		binary.Write(&b, le, t.Offset)
	}
	return b.Bytes()
}

type fixtureMeta struct {
	Size       int64 `json:"size"`
	DataOffset int64 `json:"data_offset"`
}

var fixtureModels = map[string]int{"qwen3.5-4b": 0, "gpt-oss-20b": 0, "gemma-4-12b": 0, "qwen3-coder-next": 0, "qwen3.5-35b-a3b": 0}

func TestMakeGGUFFixtures(t *testing.T) {
	if os.Getenv("KWICK_GGUF_FIXTURES") != "1" {
		t.Skip("set KWICK_GGUF_FIXTURES=1 to fetch GGUF headers from Hugging Face")
	}
	testEnv(t)
	mc, err := loadModelCatalog()
	if err != nil {
		t.Fatal(err)
	}
	os.MkdirAll("testdata/gguf", 0o755)
	for id := range fixtureModels {
		m, err := mc.find(id)
		if err != nil {
			t.Fatal(err)
		}
		g, size, err := remoteGGUF(m.fileURL(m.Files[0]))
		if err != nil {
			t.Fatal(err)
		}
		var buf bytes.Buffer
		zw, _ := gzip.NewWriterLevel(&buf, gzip.BestCompression)
		zw.Write(writeGGUFHeader(g))
		zw.Close()
		os.WriteFile("testdata/gguf/"+id+".gguf.gz", buf.Bytes(), 0o644)
		mb, _ := json.Marshal(fixtureMeta{Size: size, DataOffset: g.DataOffset})
		os.WriteFile("testdata/gguf/"+id+".json", append(mb, '\n'), 0o644)
	}
}

func loadFixture(t *testing.T, id string) (*ggufFile, int64) {
	t.Helper()
	f, err := os.Open("testdata/gguf/" + id + ".gguf.gz")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	zr, err := gzip.NewReader(f)
	if err != nil {
		t.Fatal(err)
	}
	g, err := parseGGUF(zr)
	if err != nil {
		t.Fatalf("%s: %v", id, err)
	}
	var meta fixtureMeta
	b, _ := os.ReadFile("testdata/gguf/" + id + ".json")
	if err := json.Unmarshal(b, &meta); err != nil {
		t.Fatal(err)
	}
	g.DataOffset = meta.DataOffset
	return g, meta.Size
}

func TestShapeFromRealHeaders(t *testing.T) {
	cases := []struct {
		id      string
		arch    string
		kv      int64
		swa     int64
		window  int64
		experts int64
		ctx     int64
	}{
		{"qwen3.5-4b", "qwen35", 8 * 4 * 512 * 2, 0, 0, 0, 262144},
		{"gpt-oss-20b", "gpt-oss", 12 * 8 * 128 * 2, 12 * 8 * 128 * 2, 128, 32, 131072},
		{"gemma-4-12b", "gemma4", 8 * 1 * 1024 * 2, 40 * 8 * 512 * 2, 1024, 0, 262144},
		{"qwen3-coder-next", "qwen3next", 12 * 2 * 512 * 2, 0, 0, 512, 262144},
		{"qwen3.5-35b-a3b", "qwen35moe", 10 * 2 * 512 * 2, 0, 0, 256, 262144},
	}
	for _, tc := range cases {
		g, size := loadFixture(t, tc.id)
		sh, err := shapeFromGGUF([]*ggufFile{g}, []int64{size})
		if err != nil {
			t.Fatal(err)
		}
		if sh.Arch != tc.arch || sh.KVPerTokenB != tc.kv || sh.SWAPerTokenB != tc.swa || sh.SlidingWindow != tc.window || sh.Experts != tc.experts || sh.ContextMax != tc.ctx {
			t.Errorf("%s: %+v", tc.id, sh)
		}
		if tc.id != "qwen3-coder-next" && (sh.WeightsB > size || size-sh.WeightsB > 32<<20) {
			t.Errorf("%s: weights %d of file %d", tc.id, sh.WeightsB, size)
		}
		if tc.experts > 0 && (sh.ExpertB <= 0 || sh.ExpertB >= sh.WeightsB) {
			t.Errorf("%s: expert bytes %d", tc.id, sh.ExpertB)
		}
	}
	mc := func() *ModelCatalog {
		testEnv(t)
		c, err := loadModelCatalog()
		if err != nil {
			t.Fatal(err)
		}
		return c
	}()
	for id := range fixtureModels {
		if id == "qwen3-coder-next" {
			continue
		}
		g, size := loadFixture(t, id)
		sh, _ := shapeFromGGUF([]*ggufFile{g}, []int64{size})
		m, _ := mc.find(id)
		if m.Shape.KVPerTokenB != sh.KVPerTokenB || m.Shape.SWAPerTokenB != sh.SWAPerTokenB || m.Shape.WeightsB != sh.WeightsB || m.Shape.ExpertB != sh.ExpertB {
			t.Errorf("%s: catalog shape %+v differs from the header %+v", id, *m.Shape, sh)
		}
	}
}

func TestGGUFRejectsGarbage(t *testing.T) {
	for _, b := range [][]byte{[]byte("GGML...."), []byte("GGUF\x09\x00\x00\x00"), append([]byte("GGUF\x03\x00\x00\x00"), bytes.Repeat([]byte{0xff}, 16)...)} {
		if _, err := parseGGUF(bytes.NewReader(b)); err == nil {
			t.Fatalf("accepted %q", b)
		}
	}
}

func TestComputeFit(t *testing.T) {
	testEnv(t)
	mc, err := loadModelCatalog()
	if err != nil {
		t.Fatal(err)
	}
	gpu24 := buildHardware([]GPUDevice{nv("590", "13.1")}, 65536, "amd64")
	gpu8 := buildHardware([]GPUDevice{{Vendor: "nvidia", Driver: "nvidia", DriverVersion: "590", VRAMMB: 8192}}, 32768, "amd64")
	cpu16 := buildHardware(nil, 16384, "amd64")
	cpu32 := buildHardware(nil, 32768, "amd64")
	halo := buildHardware([]GPUDevice{{Vendor: "amd", Driver: "amdgpu", VRAMMB: 512, GTTMB: 120000, Unified: true}}, 131072, "amd64")
	cases := []struct {
		id   string
		hw   Hardware
		want string
	}{
		{"qwen3.5-4b", gpu8, "gpu"},
		{"qwen3.5-9b", gpu8, "cpu-split"},
		{"qwen3.5-9b", gpu24, "gpu"},
		{"qwen3.8-27b", gpu24, "gpu"},
		{"qwen3.8-27b", gpu8, "cpu-split"},
		{"gpt-oss-20b", gpu8, "moe-offload"},
		{"qwen3.5-35b-a3b", gpu8, "moe-offload"},
		{"gpt-oss-120b", gpu24, "moe-offload"},
		{"gpt-oss-120b", halo, "gpu"},
		{"gpt-oss-120b", cpu16, "no"},
		{"qwen3.5-4b", cpu16, "cpu"},
		{"gpt-oss-20b", cpu16, "no"},
		{"gpt-oss-20b", cpu32, "cpu"},
		{"qwen3-coder-next", gpu8, "no"},
		{"qwen3-coder-next", halo, "gpu"},
	}
	for _, tc := range cases {
		m, err := mc.find(tc.id)
		if err != nil {
			t.Fatal(err)
		}
		f := computeFit(*m.Shape, tc.hw, 0)
		if f.Verdict != tc.want {
			t.Errorf("%s on %s/%d MB: %s (%s), want %s", tc.id, tc.hw.Accelerator, tc.hw.MemoryBudgetMB, f.Verdict, f.Reason, tc.want)
		}
		if f.NeedMB != f.WeightsMB+f.KVMB+f.OverheadMB || f.OverheadMB != 700 || f.Ctx != 32768 {
			t.Errorf("%s: %+v", tc.id, f)
		}
	}
	m, _ := mc.find("qwen3.5-4b")
	f := computeFit(*m.Shape, gpu8, 0)
	if f.KVMB != 1024 {
		t.Fatalf("qwen3.5-4b KV at 32K: %d MB, want 1024", f.KVMB)
	}
	big := computeFit(*m.Shape, gpu8, 131072)
	if big.KVMB != 4096 || big.MaxCtx < 131072 {
		t.Fatalf("qwen3.5-4b at 128K: %+v", big)
	}
	g, _ := mc.find("gpt-oss-20b")
	gf := computeFit(*g.Shape, gpu24, 131072)
	if gf.KVMB != 3075 {
		t.Fatalf("gpt-oss-20b KV at 128K with a 128-token window: %d MB", gf.KVMB)
	}
	items := modelItems(mc, gpu24, 0, &inferConfig{}, false)
	if best := bestModel(items, gpu24); best != "qwen3.8-27b" {
		t.Fatalf("best for a 24 GB GPU: %s", best)
	}
	if best := bestModel(modelItems(mc, cpu16, 0, &inferConfig{}, false), cpu16); best != "qwen3.5-4b" {
		t.Fatalf("best for a 16 GB CPU machine: %s", best)
	}
	if best := bestModel(modelItems(mc, cpu32, 0, &inferConfig{}, false), cpu32); best != "qwen3.5-35b-a3b" {
		t.Fatalf("best for a 32 GB CPU machine: %s", best)
	}
	if best := bestModel(modelItems(mc, halo, 0, &inferConfig{}, false), halo); best != "gpt-oss-120b" {
		t.Fatalf("best for Strix Halo: %s", best)
	}
}

func rangeServer(t *testing.T, data []byte, honourRange bool) *httptest.Server {
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if rg := r.Header.Get("Range"); rg != "" && honourRange {
			var from int
			if _, err := fmtSscanf(rg, &from); err != nil || from > len(data) {
				w.WriteHeader(416)
				return
			}
			w.Header().Set("Content-Range", "bytes "+strconv.Itoa(from)+"-"+strconv.Itoa(len(data)-1)+"/"+strconv.Itoa(len(data)))
			w.WriteHeader(206)
			w.Write(data[from:])
			return
		}
		w.Write(data)
	}))
}

func fmtSscanf(rg string, from *int) (int, error) {
	s := strings.TrimSuffix(strings.TrimPrefix(rg, "bytes="), "-")
	if i := strings.IndexByte(s, '-'); i >= 0 {
		s = s[:i]
	}
	n, err := strconv.Atoi(s)
	*from = n
	return 1, err
}

func TestResumeDownload(t *testing.T) {
	testEnv(t)
	data := bytes.Repeat([]byte("kwickos local models "), 50000)
	sum := sha256.Sum256(data)
	want := hex.EncodeToString(sum[:])
	for _, honour := range []bool{true, false} {
		srv := rangeServer(t, data, honour)
		dir := t.TempDir()
		dest := filepath.Join(dir, "m.gguf")
		os.WriteFile(dest+".part", data[:len(data)/3], 0o644)
		if err := resumeDownload(srv.URL+"/m.gguf", want, int64(len(data)), dest, nil); err != nil {
			t.Fatalf("range=%v: %v", honour, err)
		}
		got, _ := os.ReadFile(dest)
		if !bytes.Equal(got, data) || exists(dest+".part") {
			t.Fatalf("range=%v: resumed file differs", honour)
		}
		os.WriteFile(dest+".part", []byte("garbage that does not match"), 0o644)
		os.Remove(dest)
		err := resumeDownload(srv.URL+"/m.gguf", want, int64(len(data)), dest, nil)
		if honour {
			var hm hashMismatch
			if err == nil || !strings.Contains(err.Error(), "sha256 mismatch") || exists(dest) || exists(dest+".part") {
				t.Fatalf("corrupt part was accepted: %v %T", err, hm)
			}
		} else if err != nil {
			t.Fatalf("full download after a corrupt part: %v", err)
		}
		srv.Close()
	}
	srv := rangeServer(t, data, true)
	defer srv.Close()
	if err := resumeDownload(srv.URL+"/m.gguf", "nothex", 1, filepath.Join(t.TempDir(), "x"), nil); err == nil {
		t.Fatal("download without a pinned sha256")
	}
}

func TestPullAndVerify(t *testing.T) {
	h := testEnv(t)
	data := []byte("GGUF fake model weights")
	sum := sha256.Sum256(data)
	srv := rangeServer(t, data, true)
	defer srv.Close()
	m := &ModelEntry{ID: "tiny-test", Title: "t", Repo: "kwick/test", Commit: strings.Repeat("a", 40), Quant: "Q4_K_M",
		Files: []ModelFile{{Name: "dir/tiny.gguf", Size: int64(len(data)), SHA256: hex.EncodeToString(sum[:])}}, License: "mit", Shape: &ModelShape{Arch: "x"}}
	if err := m.validate(); err != nil {
		t.Fatal(err)
	}
	real := m.fileURL(m.Files[0])
	if real != "https://huggingface.co/kwick/test/resolve/"+strings.Repeat("a", 40)+"/dir/tiny.gguf" {
		t.Fatal(real)
	}
	d := filepath.Join(inferModelsDir(), m.ID, "dir")
	os.MkdirAll(d, 0o755)
	if err := resumeDownload(srv.URL+"/x", m.Files[0].SHA256, m.Files[0].Size, filepath.Join(d, "tiny.gguf"), nil); err != nil {
		t.Fatal(err)
	}
	if inst, _ := installedModel(m); inst {
		t.Fatal("installed without a manifest")
	}
	if err := verifyModel(m); err != nil {
		t.Fatal(err)
	}
	if inst, ver := installedModel(m); !inst || !ver {
		t.Fatal("not verified")
	}
	os.WriteFile(filepath.Join(d, "tiny.gguf"), []byte("GGUF fake model weightz"), 0o644)
	if err := verifyModel(m); err == nil {
		t.Fatal("tampered file verified")
	}
	if _, ver := installedModel(m); ver {
		t.Fatal("still marked verified")
	}
	if !strings.HasPrefix(inferModelsDir(), h) {
		t.Fatal(inferModelsDir())
	}
}

func TestHFPickFiles(t *testing.T) {
	sib := func(n string) hfSibling {
		s := hfSibling{Name: n, Size: 10}
		s.LFS = &struct {
			SHA256 string `json:"sha256"`
			Size   int64  `json:"size"`
		}{strings.Repeat("b", 64), 10}
		return s
	}
	sibs := []hfSibling{sib("Model-Q4_K_M.gguf"), sib("Model-Q4_K_S.gguf"), sib("Model-Q8_0.gguf"), sib("mmproj-F16.gguf"), sib("README.md"),
		sib("BIG/Model-Q4_K_M-00002-of-00002.gguf"), sib("BIG/Model-Q4_K_M-00001-of-00002.gguf"), sib("Model-UD-Q4_K_XL.gguf")}
	q, files, err := hfPickFiles(sibs[:5], "")
	if err != nil || q != "Q4_K_M" || len(files) != 1 || files[0].Name != "Model-Q4_K_M.gguf" {
		t.Fatalf("default: %s %v %v", q, files, err)
	}
	q, files, err = hfPickFiles(sibs, "q8_0")
	if err != nil || q != "Q8_0" || files[0].Name != "Model-Q8_0.gguf" {
		t.Fatalf("q8: %s %v %v", q, files, err)
	}
	if _, _, err := hfPickFiles(sibs, "Q4_K_M"); err == nil {
		t.Fatal("ambiguous quant accepted")
	}
	_, files, err = hfPickFiles(sibs[5:7], "Q4_K_M")
	if err != nil || len(files) != 2 || !strings.HasSuffix(files[0].Name, "00001-of-00002.gguf") {
		t.Fatalf("shards: %v %v", files, err)
	}
	if _, _, err := hfPickFiles(sibs, "Q2_K"); err == nil {
		t.Fatal("missing quant accepted")
	}
	q, _, err = hfPickFiles(sibs, "UD-Q4_K_XL")
	if err != nil || q != "UD-Q4_K_XL" {
		t.Fatal(q, err)
	}
}

func TestAddHFModel(t *testing.T) {
	testEnv(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/models/unsloth/Tiny-GGUF" || r.URL.Query().Get("blobs") != "true" {
			w.WriteHeader(404)
			return
		}
		io.WriteString(w, `{"id":"unsloth/Tiny-GGUF","sha":"`+strings.Repeat("c", 40)+`","gated":false,"cardData":{"license":"apache-2.0"},
		"siblings":[{"rfilename":"Tiny-Q4_K_M.gguf","size":5,"lfs":{"sha256":"`+strings.Repeat("d", 64)+`","size":5}},{"rfilename":"Tiny-Q8_0.gguf","size":9,"lfs":{"sha256":"`+strings.Repeat("e", 64)+`","size":9}}]}`)
	}))
	defer srv.Close()
	old := hfAPIBase
	hfAPIBase = srv.URL
	defer func() { hfAPIBase = old }()
	m, err := addHFModel("hf://unsloth/Tiny-GGUF:Q8_0")
	if err != nil {
		t.Fatal(err)
	}
	if m.ID != "tiny-q8_0" || m.Files[0].Size != 9 || !m.CommercialOK || m.Commit != strings.Repeat("c", 40) {
		t.Fatalf("%+v", m)
	}
	mc, err := loadModelCatalog()
	if err != nil {
		t.Fatal(err)
	}
	if x, err := mc.find("tiny-q8_0"); err != nil || x.Source != "hf" {
		t.Fatalf("user model not merged: %v", err)
	}
	if _, err := addHFModel("hf://../etc"); err == nil {
		t.Fatal("bad repo accepted")
	}
}

func TestPresetText(t *testing.T) {
	testEnv(t)
	mc, _ := loadModelCatalog()
	m, _ := mc.find("qwen3.5-4b")
	d := filepath.Join(inferModelsDir(), m.ID)
	os.MkdirAll(d, 0o755)
	f, _ := os.Create(filepath.Join(d, m.Files[0].Name))
	f.Truncate(m.Files[0].Size)
	f.Close()
	writeJSONFile(filepath.Join(d, "manifest.json"), modelManifest{ModelEntry: *m, Verified: true}, 0o644)
	cfg := &inferConfig{Model: "qwen3.5-4b"}
	hw := buildHardware([]GPUDevice{nv("590", "13.1")}, 65536, "amd64")
	txt, err := presetText(cfg, mc, hw, "/models")
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"version = 1\n", "[*]\nc = 32768\n", "fit-target = 1536\n", "[local]\nmodel = /models/qwen3.5-4b/Qwen3.5-4B-Q4_K_M.gguf\n", "[qwen3.5-4b]\n", "load-on-startup = false"} {
		if !strings.Contains(txt, want) {
			t.Fatalf("preset lacks %q:\n%s", want, txt)
		}
	}
	cfg.Model = "gpt-oss-20b"
	if _, err := presetText(cfg, mc, hw, "/models"); err == nil {
		t.Fatal("preset for a model that is not downloaded")
	}
	args := strings.Join(serverArgs(cfg, "/e", "/r", hw), " ")
	for _, want := range []string{"/e/llama-server --host 127.0.0.1 --port 11435", "--api-key-file /r/api-key", "--models-preset /r/models.ini", "--sleep-idle-seconds 900", "--models-memory-margin 1536", "--no-webui"} {
		if !strings.Contains(args, want) {
			t.Fatalf("args lack %q: %s", want, args)
		}
	}
	bw := strings.Join(inferBwrapArgs("/eng", "/mod", "", "cuda13"), " ")
	for _, want := range []string{"--unshare-all --share-net", "--ro-bind /eng /eng", "--ro-bind /mod /mod", "--tmpfs /home", "--tmpfs /run"} {
		if !strings.Contains(bw, want) {
			t.Fatalf("bwrap lacks %q: %s", want, bw)
		}
	}
	if strings.Contains(bw, homeDir()) || strings.Contains(bw, "dbus") {
		t.Fatalf("bwrap exposes the home or D-Bus: %s", bw)
	}
	if strings.Contains(strings.Join(inferBwrapArgs("/eng", "/mod", "", "cpu"), " "), "/dev/dri") {
		t.Fatal("cpu backend gets GPU devices")
	}
}

func TestTakeLocalFlag(t *testing.T) {
	testEnv(t)
	got := takeLocalFlag([]string{"run", "--local", "aider", "--", "--local"})
	if strings.Join(got, " ") != "run aider -- --local" || !localRun {
		t.Fatal(got)
	}
	localRun = false
	got = takeLocalFlag([]string{"list", "--local"})
	if len(got) != 2 || localRun {
		t.Fatal(got)
	}
	localRun = true
	m := map[string]string{inferKeyEnv: "k", "ANTHROPIC_API_KEY": "real"}
	applyLocalRun(&Entry{Name: "claude-code"}, m)
	if m["ANTHROPIC_BASE_URL"] != "http://127.0.0.1:11435" || m["ANTHROPIC_AUTH_TOKEN"] != "k" || m["ANTHROPIC_API_KEY"] != "" || m["ANTHROPIC_MODEL"] != "local" {
		t.Fatal(m)
	}
	m = map[string]string{inferKeyEnv: "k"}
	applyLocalRun(&Entry{Name: "aider"}, m)
	if m["OPENAI_API_BASE"] != "http://127.0.0.1:11435/v1" || m["OPENAI_API_KEY"] != "k" || m["AIDER_MODEL"] != "openai/local" {
		t.Fatal(m)
	}
	localRun = false
}

func readGolden(t *testing.T, p string) string {
	t.Helper()
	b, err := os.ReadFile(p)
	if err != nil {
		if os.IsNotExist(err) {
			return ""
		}
		t.Fatal(err)
	}
	return string(b)
}

func TestConnectGolden(t *testing.T) {
	update := os.Getenv("KWICK_UPDATE_GOLDEN") == "1"
	agents := []struct {
		name  string
		files []string
	}{
		{"opencode", []string{".config/opencode/opencode.json"}},
		{"codex", []string{".codex/config.toml"}},
		{"goose", []string{".config/goose/config.yaml", ".config/goose/custom_providers/kwickos-local.json"}},
		{"hermes", []string{".hermes/config.yaml"}},
		{"openclaw", []string{".openclaw/openclaw.json"}},
		{"omp", []string{".omp/agent/models.yml", ".omp/agent/config.yml"}},
	}
	for _, variant := range []string{"existing", "empty"} {
		for _, a := range agents {
			h := testEnv(t)
			base := filepath.Join("testdata/connect", variant, a.name)
			before := map[string]string{}
			for _, f := range a.files {
				s := readGolden(t, filepath.Join(base, "before", f))
				before[f] = s
				if s != "" {
					os.MkdirAll(filepath.Dir(filepath.Join(h, f)), 0o755)
					os.WriteFile(filepath.Join(h, f), []byte(s), 0o600)
				}
			}
			cfg := &inferConfig{Model: "qwen3.5-4b", Connected: map[string]*connRecord{}}
			for round := 0; round < 2; round++ {
				if err := connectAgent(cfg, a.name, true); err != nil {
					t.Fatalf("%s/%s connect: %v", variant, a.name, err)
				}
				if !connectedNow(a.name) {
					t.Fatalf("%s/%s not detected as connected", variant, a.name)
				}
				for _, f := range a.files {
					got := readGolden(t, filepath.Join(h, f))
					gp := filepath.Join(base, "after", f)
					if update && round == 0 {
						os.MkdirAll(filepath.Dir(gp), 0o755)
						os.WriteFile(gp, []byte(got), 0o644)
					}
					if want := readGolden(t, gp); got != want {
						t.Fatalf("%s/%s round %d: %s differs from golden:\n%s\n--- want ---\n%s", variant, a.name, round, f, got, want)
					}
				}
			}
			if err := connectAgent(cfg, a.name, false); err != nil {
				t.Fatalf("%s/%s disconnect: %v", variant, a.name, err)
			}
			if connectedNow(a.name) {
				t.Fatalf("%s/%s still connected", variant, a.name)
			}
			for _, f := range a.files {
				got := readGolden(t, filepath.Join(h, f))
				want := before[f]
				if variant == "empty" {
					if strings.Contains(got, localMarker) || strings.Contains(got, "11435") {
						t.Fatalf("empty/%s: %s still mentions the local endpoint:\n%s", a.name, f, got)
					}
					continue
				}
				if got != want {
					t.Fatalf("%s/%s: disconnect did not restore %s:\n%s\n--- want ---\n%s", variant, a.name, f, got, want)
				}
			}
		}
	}
}

func TestCybaraWiring(t *testing.T) {
	h := testEnv(t)
	type call struct{ method, path, auth, body string }
	var calls []call
	providers := []map[string]any{{"id": "p-anthropic", "provider": "anthropic", "name": "Anthropic", "is_default": true}}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		calls = append(calls, call{r.Method, r.URL.Path, r.Header.Get("Authorization"), string(b)})
		if r.Header.Get("Authorization") != "Bearer cyb-token" {
			w.WriteHeader(401)
			return
		}
		switch {
		case r.Method == "GET" && r.URL.Path == "/api/providers":
			json.NewEncoder(w).Encode(providers)
		case r.Method == "POST" && r.URL.Path == "/api/providers":
			var body map[string]any
			json.Unmarshal(b, &body)
			body["id"] = "p-local"
			providers[0]["is_default"] = false
			providers = append(providers, body)
			json.NewEncoder(w).Encode(map[string]any{"id": "p-local"})
		case r.Method == "PUT":
			json.NewEncoder(w).Encode(map[string]any{"success": true})
		case r.Method == "DELETE":
			providers = providers[:1]
			json.NewEncoder(w).Encode(map[string]any{"success": true})
		default:
			json.NewEncoder(w).Encode(map[string]any{"models": []any{}})
		}
	}))
	defer srv.Close()
	t.Setenv("CYBARA_API", srv.URL)
	os.MkdirAll(filepath.Join(h, ".cybara"), 0o700)
	os.WriteFile(filepath.Join(h, ".cybara", "api_key"), []byte("cyb-token\n"), 0o600)
	cfg := &inferConfig{Model: "qwen3.5-4b", Connected: map[string]*connRecord{}}
	if err := connectAgent(cfg, "cybara", true); err != nil {
		t.Fatal(err)
	}
	key, err := inferKey(false)
	if err != nil || !strings.HasPrefix(key, "kwi-") {
		t.Fatalf("key %q %v", key, err)
	}
	var post call
	for _, c := range calls {
		if c.method == "POST" && c.path == "/api/providers" {
			post = c
		}
	}
	var body map[string]any
	json.Unmarshal([]byte(post.body), &body)
	if body["provider"] != "custom" || body["base_url"] != "http://127.0.0.1:11435/v1" || body["api_key"] != key || body["is_default"] != true || body["name"] != cybaraName {
		t.Fatalf("POST body %v", body)
	}
	rec := cfg.Connected["cybara"]
	if rec == nil || rec.ID != "p-local" || rec.Previous["default_provider"] != "p-anthropic" {
		t.Fatalf("record %+v", rec)
	}
	b, _ := json.Marshal(cfg)
	if strings.Contains(string(b), key) {
		t.Fatal("the key was stored in the inference config")
	}
	calls = nil
	if err := connectAgent(cfg, "cybara", true); err != nil {
		t.Fatal(err)
	}
	for _, c := range calls {
		if c.method == "POST" && c.path == "/api/providers" {
			t.Fatal("second connect created a second provider")
		}
	}
	calls = nil
	if err := connectAgent(cfg, "cybara", false); err != nil {
		t.Fatal(err)
	}
	var del, restore bool
	for _, c := range calls {
		del = del || (c.method == "DELETE" && c.path == "/api/providers/p-local")
		restore = restore || (c.method == "PUT" && c.path == "/api/providers/p-anthropic" && strings.Contains(c.body, `"is_default":true`))
	}
	if !del || !restore || cfg.Connected["cybara"] != nil {
		t.Fatalf("disconnect calls %+v", calls)
	}
	t.Setenv("CYBARA_API", "http://127.0.0.1:1")
	err = connectAgent(cfg, "cybara", true)
	if err == nil || !strings.Contains(err.Error(), "cybara start") || !strings.Contains(err.Error(), "endpoint.json") {
		t.Fatalf("unreachable gateway: %v", err)
	}
}

func TestEndpointHasNoKey(t *testing.T) {
	testEnv(t)
	key, err := inferKey(true)
	if err != nil {
		t.Fatal(err)
	}
	cfg := &inferConfig{Model: "qwen3.5-4b"}
	if err := writeEndpoint(cfg); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(endpointPath())
	var ep map[string]any
	json.Unmarshal(b, &ep)
	if ep["url"] != "http://127.0.0.1:11435/v1" || ep["model"] != "local" || ep["key_env"] != inferKeyEnv || ep["model_id"] != "qwen3.5-4b" {
		t.Fatal(string(b))
	}
	if strings.Contains(string(b), key) {
		t.Fatal("endpoint.json contains the key")
	}
	st := buildStatus()
	sb, _ := json.Marshal(st)
	if strings.Contains(string(sb), key) {
		t.Fatal("status contains the key")
	}
	if st.Schema != 1 || st.Service.KeyEnv != inferKeyEnv || !st.Service.KeySet || st.Service.Port != 11435 {
		t.Fatalf("%+v", st.Service)
	}
}

func TestInferenceTools(t *testing.T) {
	testEnv(t)
	names := map[string]string{}
	for _, x := range toolTable() {
		names[x.Name] = x.Cap
	}
	want := map[string]string{"inference_status": "system.read", "inference_models": "system.read", "inference_start": "inference.manage", "inference_stop": "inference.manage", "inference_pull": "inference.manage"}
	for n, c := range want {
		if names[n] != c {
			t.Fatalf("%s: capability %q, want %q", n, names[n], c)
		}
	}
	ci, ok := capByName("inference.manage")
	if !ok || ci.Default != "ask" {
		t.Fatal(ci)
	}
	d := pullDetail(nil, map[string]any{"model": "gpt-oss-20b"})
	if !strings.Contains(d, "11.3 GB") || !strings.Contains(d, "apache-2.0") {
		t.Fatal(d)
	}
	var out bytes.Buffer
	s := newServer("external", nil, false)
	s.serve(strings.NewReader(`{"jsonrpc":"2.0","id":1,"method":"resources/read","params":{"uri":"kwickos://docs/inference"}}`+"\n"), &out)
	if !strings.Contains(out.String(), "kwickos://docs/inference") {
		t.Fatal(out.String())
	}
}

func TestParseIopts(t *testing.T) {
	o, err := parseIopts([]string{"fit", "qwen3.5-4b", "--ctx", "64K", "--json", "--backend=vulkan"})
	if err != nil || o.ctx != 65536 || !o.json || o.backend != "vulkan" || strings.Join(o.args, " ") != "fit qwen3.5-4b" {
		t.Fatalf("%+v %v", o, err)
	}
	if _, err := parseIopts([]string{"models", "--bogus"}); err == nil {
		t.Fatal("unknown option accepted")
	}
}
