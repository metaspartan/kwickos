package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"strings"
)

const kpkgVersion = "0.1.0"

const dpkgCompatVersion = "1.22.21"

type Config struct {
	Root, Admin, Lists, Cache string
	Arch                      string
	Foreign                   []string
	ForceArch                 bool
	Yes, DryRun, Reinstall    bool
	Recommends                bool
	KeepDebs, DownloadOnly    bool
	Purge, AutoRemove         bool
	AllowHeld, IndexXZ        bool
	AllowUnauth               bool
	ForceOverwrite            bool
	PathFilters               []filterRule
	Quiet                     int
	TargetRelease             string
	Avoid                     map[string]bool
}

var defaultAvoid = []string{"systemd", "systemd-sysv", "libpam-systemd", "dbus-user-session", "systemd-timesyncd"}

var cfg = Config{Root: "/"}

func debArch() string {
	if a := os.Getenv("KPKG_ARCH"); a != "" {
		return a
	}
	switch runtime.GOARCH {
	case "amd64":
		return "amd64"
	case "arm64":
		return "arm64"
	case "riscv64":
		return "riscv64"
	case "arm":
		return "armhf"
	case "386":
		return "i386"
	case "ppc64le":
		return "ppc64el"
	case "s390x":
		return "s390x"
	case "loong64":
		return "loong64"
	}
	return runtime.GOARCH
}

func setupPaths() {
	if r := os.Getenv("KPKG_ROOT"); r != "" && cfg.Root == "/" {
		cfg.Root = r
	}
	cfg.Root, _ = filepath.Abs(cfg.Root)
	cfg.Admin = filepath.Join(cfg.Root, "var/lib/dpkg")
	cfg.Lists = filepath.Join(cfg.Root, "var/lib/apt/lists")
	cfg.Cache = filepath.Join(cfg.Root, "var/cache/apt/archives")
	cfg.Arch = debArch()
	cfg.Foreign = loadForeignArches()
	cfg.Avoid = map[string]bool{}
	for _, n := range defaultAvoid {
		cfg.Avoid[n] = true
	}
	if data, err := os.ReadFile(filepath.Join(cfg.Root, "etc/kpkg.conf")); err == nil {
		for _, l := range strings.Split(string(data), "\n") {
			k, v, ok := strings.Cut(l, "=")
			if !ok || strings.HasPrefix(strings.TrimSpace(l), "#") {
				continue
			}
			v = strings.TrimSpace(v)
			on := v == "true" || v == "yes" || v == "1"
			switch strings.TrimSpace(k) {
			case "install-recommends":
				cfg.Recommends = on
			case "keep-downloaded-packages":
				cfg.KeepDebs = on
			case "assume-yes":
				cfg.Yes = on
			case "index-compression":
				cfg.IndexXZ = v == "xz"
			case "avoid":
				cfg.Avoid = map[string]bool{}
				for _, n := range strings.Fields(v) {
					cfg.Avoid[n] = true
				}
			}
		}
	}
}

func die(err error) {
	fmt.Fprintf(os.Stderr, "E: %v\n", err)
	os.Exit(100)
}

func main() {
	tuneGC()
	name := filepath.Base(os.Args[0])
	args := os.Args[1:]
	if name == "kpkg" && len(args) > 0 {
		switch args[0] {
		case "apk", "apt", "apt-get", "apt-cache", "apt-mark", "dpkg", "dpkg-query", "dpkg-deb", "update-alternatives",
			"dpkg-trigger", "dpkg-divert", "dpkg-maintscript-helper", "dpkg-statoverride", "dpkg-architecture":
			name, args = args[0], args[1:]
		}
	}
	var rc int
	switch name {
	case "apk":
		rc = mainApk(args)
	case "dpkg":
		rc = mainDpkg(args)
	case "dpkg-query":
		rc = mainDpkgQuery(args)
	case "dpkg-deb":
		rc = mainDpkgDeb(args)
	case "update-alternatives":
		setupPaths()
		rc = mainAlternatives(args)
	case "dpkg-trigger":
		rc = mainDpkgTrigger(args)
	case "dpkg-divert":
		rc = 0
	case "dpkg-statoverride":
		rc = mainStatoverride(args)
	case "dpkg-maintscript-helper":
		rc = mainMaintscriptHelper(args)
	case "dpkg-architecture":
		setupPaths()
		fmt.Printf("DEB_HOST_ARCH=%s\nDEB_BUILD_ARCH=%s\n", cfg.Arch, cfg.Arch)
	case "apt-cache":
		rc = mainAptCache(args)
	case "apt-mark":
		rc = mainAptMark(args)
	default:
		rc = mainApt(name, args)
	}
	os.Exit(rc)
}

var memTotal = readMemTotal

func readMemTotal() int64 {
	data, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		return 0
	}
	for _, l := range strings.Split(string(data), "\n") {
		if v, ok := strings.CutPrefix(l, "MemTotal:"); ok {
			f := strings.Fields(v)
			if len(f) > 0 {
				var n int64
				fmt.Sscan(f[0], &n)
				return n << 10
			}
		}
	}
	return 0
}

func tuneGC() { tuneGCFor(memTotal()) }

func tuneGCFor(total int64) {
	if total < 1<<30 {
		debug.SetGCPercent(50)
		debug.SetMemoryLimit(max(192<<20, total/2))
		return
	}
	debug.SetGCPercent(200)
	debug.SetMemoryLimit(max(256<<20, total/4))
}

func relaxGC() func() {
	pct := debug.SetGCPercent(-1)
	lim := debug.SetMemoryLimit(-1)
	if total := memTotal(); total > 0 {
		debug.SetMemoryLimit(max(lim, total/2))
	}
	return func() {
		debug.SetMemoryLimit(lim)
		debug.SetGCPercent(pct)
	}
}
