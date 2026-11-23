package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

type GPUDevice struct {
	Index         int    `json:"index"`
	Vendor        string `json:"vendor"`
	Name          string `json:"name"`
	PCI           string `json:"pci,omitempty"`
	Card          string `json:"card,omitempty"`
	VRAMMB        int64  `json:"vram_mb"`
	GTTMB         int64  `json:"gtt_mb"`
	ComputeCap    string `json:"compute_cap"`
	Driver        string `json:"driver"`
	DriverVersion string `json:"driver_version,omitempty"`
	CUDAVersion   string `json:"cuda_version,omitempty"`
	Unified       bool   `json:"unified"`
	Display       bool   `json:"display"`
}

type Hardware struct {
	Arch           string      `json:"arch"`
	RAMMB          int64       `json:"ram_mb"`
	MemoryBudgetMB int64       `json:"memory_budget_mb"`
	RAMBudgetMB    int64       `json:"ram_budget_mb"`
	VRAMMB         int64       `json:"vram_mb"`
	Unified        bool        `json:"unified"`
	Accelerator    string      `json:"accelerator"`
	Devices        []GPUDevice `json:"devices"`
}

var sysRoot = ""

func sysPath(p string) string { return filepath.Join(sysRoot+"/", p) }

func readTrim(p string) string {
	b, err := os.ReadFile(p)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

func readInt64(p string) int64 {
	n, _ := strconv.ParseInt(readTrim(p), 10, 64)
	return n
}

func pciVendor(id string) string {
	switch strings.ToLower(id) {
	case "0x10de":
		return "nvidia"
	case "0x1002":
		return "amd"
	case "0x8086":
		return "intel"
	case "0x1af4", "0x15ad", "0x1234", "0x1414", "0x1b36", "0x1ab8", "0x80ee":
		return "vm"
	}
	return ""
}

func pciName(vendor, device string) string {
	v := strings.TrimPrefix(strings.ToLower(vendor), "0x")
	d := strings.TrimPrefix(strings.ToLower(device), "0x")
	for _, p := range []string{"/usr/share/misc/pci.ids", "/usr/share/hwdata/pci.ids"} {
		f, err := os.Open(sysPath(p))
		if err != nil {
			continue
		}
		sc := bufio.NewScanner(f)
		in := false
		for sc.Scan() {
			l := sc.Text()
			if strings.HasPrefix(l, "#") || l == "" {
				continue
			}
			if !strings.HasPrefix(l, "\t") {
				in = strings.HasPrefix(l, v+"  ")
				continue
			}
			if in && strings.HasPrefix(l, "\t"+d+"  ") {
				f.Close()
				return strings.TrimSpace(l[len(d)+3:])
			}
		}
		f.Close()
	}
	return ""
}

func cardHasDisplay(card string) bool {
	ms, _ := filepath.Glob(sysPath("/sys/class/drm/" + card + "-*/status"))
	for _, m := range ms {
		if readTrim(m) == "connected" {
			return true
		}
	}
	return false
}

func memTotalMB() int64 {
	f, err := os.Open(sysPath("/proc/meminfo"))
	if err != nil {
		return 0
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		fs := strings.Fields(sc.Text())
		if len(fs) >= 2 && fs[0] == "MemTotal:" {
			kb, _ := strconv.ParseInt(fs[1], 10, 64)
			return kb / 1024
		}
	}
	return 0
}

type nvSMI struct {
	name, pci, cc, driver string
	memMB                 int64
	memNA                 bool
}

var nvidiaSMI = func() ([]nvSMI, string) {
	if lookPath("nvidia-smi") == "" {
		return nil, ""
	}
	out, err := runTimeout(10*time.Second, "nvidia-smi", "--query-gpu=name,pci.bus_id,memory.total,compute_cap,driver_version", "--format=csv,noheader,nounits")
	if err != nil {
		return nil, ""
	}
	var rows []nvSMI
	for _, l := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		f := strings.Split(l, ",")
		if len(f) < 5 {
			continue
		}
		for i := range f {
			f[i] = strings.TrimSpace(f[i])
		}
		r := nvSMI{name: f[0], pci: strings.ToLower(f[1]), cc: f[3], driver: f[4]}
		if n, err := strconv.ParseInt(f[2], 10, 64); err == nil {
			r.memMB = n
		} else {
			r.memNA = true
		}
		rows = append(rows, r)
	}
	cuda := ""
	if hdr, err := runTimeout(10*time.Second, "nvidia-smi"); err == nil {
		s := string(hdr)
		if i := strings.Index(s, "CUDA Version:"); i >= 0 {
			if fs := strings.Fields(s[i+len("CUDA Version:"):]); len(fs) > 0 {
				cuda = fs[0]
			}
		}
	}
	return rows, cuda
}

func nvidiaKernelVersion() string {
	s := readTrim(sysPath("/proc/driver/nvidia/version"))
	for _, f := range strings.Fields(s) {
		if len(f) > 3 && f[0] >= '3' && f[0] <= '9' && strings.Count(f, ".") >= 1 {
			if _, err := strconv.Atoi(strings.Split(f, ".")[0]); err == nil {
				return f
			}
		}
	}
	return readTrim(sysPath("/sys/module/nvidia/version"))
}

func pciAddr(card string) string {
	p, err := filepath.EvalSymlinks(sysPath("/sys/class/drm/" + card + "/device"))
	if err != nil {
		return ""
	}
	return strings.ToLower(filepath.Base(p))
}

func normPCI(a string) string {
	a = strings.ToLower(a)
	if i := strings.Index(a, ":"); i > 4 {
		a = a[i-4:]
	}
	return a
}

func detectGPUs() []GPUDevice {
	cards, _ := filepath.Glob(sysPath("/sys/class/drm/card[0-9]*"))
	sort.Slice(cards, func(i, j int) bool {
		a, _ := strconv.Atoi(strings.TrimPrefix(filepath.Base(cards[i]), "card"))
		b, _ := strconv.Atoi(strings.TrimPrefix(filepath.Base(cards[j]), "card"))
		return a < b
	})
	var devs []GPUDevice
	seen := map[string]bool{}
	var nv []nvSMI
	cuda := ""
	nvLoaded := false
	for _, c := range cards {
		card := filepath.Base(c)
		if strings.Contains(card, "-") {
			continue
		}
		dev := filepath.Join(c, "device")
		drv := ""
		if t, err := os.Readlink(filepath.Join(dev, "driver")); err == nil {
			drv = filepath.Base(t)
		}
		vendorID := readTrim(filepath.Join(dev, "vendor"))
		vendor := pciVendor(vendorID)
		of := readTrim(filepath.Join(dev, "of_node/compatible"))
		if vendor == "" {
			switch {
			case drv == "asahi" || strings.Contains(of, "apple,"):
				vendor = "apple"
			case drv == "v3d" || drv == "vc4":
				vendor = "rpi"
			case drv != "":
				vendor = drv
			default:
				continue
			}
		}
		addr := pciAddr(card)
		key := addr
		if key == "" {
			key = card
		}
		if seen[key] {
			continue
		}
		if drv == "vc4" && vendor == "rpi" {
			continue
		}
		seen[key] = true
		d := GPUDevice{Index: len(devs), Vendor: vendor, Card: card, Driver: drv, Display: cardHasDisplay(card)}
		if strings.Contains(addr, ":") {
			d.PCI = addr
		}
		d.Name = pciName(vendorID, readTrim(filepath.Join(dev, "device")))
		switch vendor {
		case "amd":
			d.VRAMMB = readInt64(filepath.Join(dev, "mem_info_vram_total")) / (1 << 20)
			d.GTTMB = readInt64(filepath.Join(dev, "mem_info_gtt_total")) / (1 << 20)
			d.DriverVersion = readTrim(sysPath("/sys/module/amdgpu/version"))
			if p := readTrim(filepath.Join(dev, "product_name")); p != "" {
				d.Name = p
			}
			_, vendorErr := os.Stat(filepath.Join(dev, "mem_info_vram_vendor"))
			d.Unified = (vendorErr != nil && d.VRAMMB > 0) || (d.VRAMMB > 0 && d.VRAMMB < 4096 && d.GTTMB > d.VRAMMB)
			if t := readTrim(filepath.Join(dev, "ip_discovery/die/0/GC/0/major")); t != "" {
				d.ComputeCap = "gfx" + t + readTrim(filepath.Join(dev, "ip_discovery/die/0/GC/0/minor")) + readTrim(filepath.Join(dev, "ip_discovery/die/0/GC/0/revision"))
			}
		case "intel":
			d.Unified = true
			devID := strings.ToLower(readTrim(filepath.Join(dev, "device")))
			if strings.HasPrefix(devID, "0x56") || strings.HasPrefix(devID, "0xe2") {
				d.Unified = false
			}
			for _, p := range []string{"tile0/vram0/size", "lmem_total_bytes"} {
				if n := readInt64(filepath.Join(dev, p)); n > 0 {
					d.VRAMMB = n / (1 << 20)
				}
			}
		case "nvidia":
			if drv == "nvidia" {
				nvLoaded = true
			}
		case "apple", "rpi":
			d.Unified = true
		}
		devs = append(devs, d)
	}
	if nvLoaded || exists(sysPath("/proc/driver/nvidia/version")) {
		nv, cuda = nvidiaSMI()
		kv := nvidiaKernelVersion()
		matched := map[int]bool{}
		for i := range devs {
			if devs[i].Vendor != "nvidia" {
				continue
			}
			for j, r := range nv {
				if matched[j] || (devs[i].PCI != "" && normPCI(r.pci) != normPCI(devs[i].PCI)) {
					continue
				}
				matched[j] = true
				devs[i].Name = r.name
				devs[i].ComputeCap = r.cc
				devs[i].DriverVersion = r.driver
				devs[i].VRAMMB = r.memMB
				if r.memNA {
					devs[i].Unified = true
				}
				break
			}
			if devs[i].DriverVersion == "" {
				devs[i].DriverVersion = kv
			}
			devs[i].CUDAVersion = cuda
		}
		for j, r := range nv {
			if matched[j] {
				continue
			}
			d := GPUDevice{Index: len(devs), Vendor: "nvidia", Name: r.name, PCI: normPCI(r.pci), VRAMMB: r.memMB, ComputeCap: r.cc, Driver: "nvidia", DriverVersion: r.driver, CUDAVersion: cuda, Unified: r.memNA}
			devs = append(devs, d)
		}
	}
	if devs == nil {
		devs = []GPUDevice{}
	}
	return devs
}

func displayHeadroomMB(d GPUDevice) int64 {
	if d.Display {
		return 1536
	}
	return 512
}

func ramReserveMB(ram int64) int64 {
	r := ram / 8
	if r < 2048 {
		r = 2048
	}
	return r
}

func computeVendor(devs []GPUDevice) string {
	tot := map[string]int64{}
	order := []string{}
	for _, d := range devs {
		switch d.Vendor {
		case "nvidia", "amd", "intel", "apple":
		default:
			continue
		}
		if d.Vendor == "nvidia" && d.Driver != "nvidia" && d.DriverVersion == "" {
			continue
		}
		if _, ok := tot[d.Vendor]; !ok {
			order = append(order, d.Vendor)
		}
		tot[d.Vendor] += d.VRAMMB + 1
	}
	best := ""
	for _, v := range order {
		if best == "" || tot[v] > tot[best] {
			best = v
		}
	}
	return best
}

func buildHardware(devs []GPUDevice, ramMB int64, arch string) Hardware {
	h := Hardware{Arch: arch, RAMMB: ramMB, Devices: devs}
	reserve := ramReserveMB(ramMB)
	h.RAMBudgetMB = ramMB - reserve
	if h.RAMBudgetMB < 0 {
		h.RAMBudgetMB = 0
	}
	h.MemoryBudgetMB = h.RAMBudgetMB
	h.Accelerator = "cpu"
	v := computeVendor(devs)
	if v == "" {
		return h
	}
	var vram, budget, unifiedPool int64
	unified := false
	for _, d := range devs {
		if d.Vendor != v {
			continue
		}
		if d.Unified {
			unified = true
			pool := d.VRAMMB + d.GTTMB
			if d.Vendor == "apple" || d.Vendor == "nvidia" || pool == 0 {
				pool = ramMB
			}
			if pool > unifiedPool {
				unifiedPool = pool
			}
			continue
		}
		if d.VRAMMB <= 0 {
			continue
		}
		vram += d.VRAMMB
		b := d.VRAMMB - displayHeadroomMB(d)
		if b > 0 {
			budget += b
		}
	}
	h.Accelerator = v
	if budget > 0 {
		h.VRAMMB = vram
		h.MemoryBudgetMB = budget
		return h
	}
	if unified {
		h.Unified = true
		lim := ramMB - reserve
		if unifiedPool > 0 && unifiedPool < lim {
			lim = unifiedPool
		}
		if lim < 0 {
			lim = 0
		}
		h.VRAMMB = lim
		h.MemoryBudgetMB = lim
		return h
	}
	h.Accelerator = "cpu"
	return h
}

func detectHardware() Hardware {
	return buildHardware(detectGPUs(), memTotalMB(), hostArch())
}

type backendChoice struct {
	Backend string `json:"backend"`
	Reason  string `json:"reason"`
}

func driverMajor(v string) int {
	n, _ := strconv.Atoi(strings.Split(strings.TrimSpace(v), ".")[0])
	return n
}

func vulkanICD() bool {
	for _, d := range []string{"/usr/share/vulkan/icd.d", "/etc/vulkan/icd.d"} {
		ms, _ := filepath.Glob(sysPath(d + "/*.json"))
		if len(ms) > 0 {
			return true
		}
	}
	return false
}

var hipRuntime = func() bool {
	out, err := runTimeout(5*time.Second, "/sbin/ldconfig", "-p")
	if err != nil {
		return false
	}
	return strings.Contains(string(out), "libamdhip64.so.7") && strings.Contains(string(out), "librocblas.so.5")
}

func backendAvailable(e *Entry, backend, arch string) bool {
	if e == nil {
		return false
	}
	_, ok := e.Backends[backend][arch]
	return ok
}

func selectBackend(e *Entry, hw Hardware, override string, icd bool) (backendChoice, error) {
	arch := hw.Arch
	if override != "" {
		if !backendAvailable(e, override, arch) {
			return backendChoice{}, fmt.Errorf("backend %q is not published for %s (available: %s)", override, arch, strings.Join(backendList(e, arch), ", "))
		}
		return backendChoice{override, "chosen with --backend or KWICK_INFERENCE_BACKEND"}, nil
	}
	if len(backendList(e, arch)) == 0 {
		return backendChoice{}, fmt.Errorf("llama.cpp publishes no build for %s; build it from source", arch)
	}
	vk := func(why string) backendChoice {
		if !icd {
			return backendChoice{"cpu", why + ", but no Vulkan driver is installed (kwick-gpu install adds mesa-vulkan-drivers); using the CPU"}
		}
		if !backendAvailable(e, "vulkan", arch) {
			return backendChoice{"cpu", why + ", but there is no Vulkan build for " + arch}
		}
		return backendChoice{"vulkan", why}
	}
	switch hw.Accelerator {
	case "nvidia":
		var drv, cuda string
		for _, d := range hw.Devices {
			if d.Vendor == "nvidia" && d.DriverVersion != "" {
				drv, cuda = d.DriverVersion, d.CUDAVersion
				break
			}
		}
		major := driverMajor(drv)
		cudaMajor := driverMajor(cuda)
		if cudaMajor >= 13 || (cudaMajor == 0 && major >= 580) {
			if backendAvailable(e, "cuda13", arch) {
				return backendChoice{"cuda13", "NVIDIA driver " + drv + " supports CUDA 13"}, nil
			}
		}
		if cudaMajor == 12 || (cudaMajor == 0 && major >= 525) || cudaMajor >= 13 {
			if backendAvailable(e, "cuda12", arch) {
				return backendChoice{"cuda12", "NVIDIA driver " + drv + " supports CUDA 12"}, nil
			}
		}
		return vk("NVIDIA driver " + drv + " is too old for the CUDA builds"), nil
	case "amd":
		return vk("AMD GPU: Vulkan (RADV) is the default; ROCm is opt-in with --backend rocm"), nil
	case "intel":
		return vk("Intel GPU: Vulkan (ANV)"), nil
	case "apple":
		return backendChoice{"cpu", "Apple Silicon (Asahi): CPU build; Vulkan is opt-in with --backend vulkan"}, nil
	}
	for _, d := range hw.Devices {
		if d.Vendor == "nvidia" {
			return vk("NVIDIA GPU without the NVIDIA driver (nouveau): Vulkan through NVK"), nil
		}
	}
	return backendChoice{"cpu", "no supported GPU found"}, nil
}

func backendList(e *Entry, arch string) []string {
	var out []string
	if e == nil {
		return out
	}
	for _, b := range []string{"cpu", "vulkan", "cuda12", "cuda13", "rocm"} {
		if backendAvailable(e, b, arch) {
			out = append(out, b)
		}
	}
	return out
}

func gpuDeviceNodes(backend string) []string {
	if backend == "cpu" {
		return nil
	}
	var out []string
	for _, p := range []string{"/dev/dri", "/dev/kfd"} {
		if exists(p) {
			out = append(out, p)
		}
	}
	if backend == "cuda12" || backend == "cuda13" || backend == "vulkan" {
		ms, _ := filepath.Glob("/dev/nvidia*")
		out = append(out, ms...)
	}
	return out
}

func cmdInferGPU(o iopts) error {
	hw := detectHardware()
	if o.json {
		emitJSON(map[string]any{"schema": 1, "hardware": hw})
		return nil
	}
	printHardware(hw)
	return nil
}

func printHardware(hw Hardware) {
	fmt.Printf("Memory: %d MB RAM; budget for models %d MB (%s)\n", hw.RAMMB, hw.MemoryBudgetMB, map[bool]string{true: "unified memory", false: hw.Accelerator}[hw.Unified])
	if len(hw.Devices) == 0 {
		fmt.Println("GPUs: none")
	}
	for _, d := range hw.Devices {
		extra := ""
		if d.ComputeCap != "" {
			extra += " cc " + d.ComputeCap
		}
		if d.DriverVersion != "" {
			extra += " driver " + d.DriverVersion
		}
		fmt.Printf("GPU %d: %s %s, VRAM %d MB, GTT %d MB, %s%s%s\n", d.Index, d.Vendor, d.Name, d.VRAMMB, d.GTTMB, d.Driver, extra, map[bool]string{true: ", drives a display", false: ""}[d.Display])
	}
}
