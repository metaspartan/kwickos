package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"image"
	"image/png"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"
)

type tool struct {
	Name        string
	Title       string
	Description string
	Cap         string
	Schema      map[string]any
	ReadOnly    bool
	Destructive bool
	noSession   bool
	fn          func(s *Server, a map[string]any) (toolResult, error)
	detail      func(s *Server, a map[string]any) string
	precheck    func(s *Server, a map[string]any) error
}

func (t tool) describe() map[string]any {
	schema := t.Schema
	if schema == nil {
		schema = obj(nil)
	}
	return map[string]any{
		"name":        t.Name,
		"title":       t.Title,
		"description": t.Description + " Needs the '" + t.Cap + "' permission.",
		"inputSchema": schema,
		"annotations": map[string]any{"title": t.Title, "readOnlyHint": t.ReadOnly, "destructiveHint": t.Destructive, "openWorldHint": false},
	}
}

func obj(props map[string]any, required ...string) map[string]any {
	if props == nil {
		props = map[string]any{}
	}
	m := map[string]any{"type": "object", "properties": props, "additionalProperties": false}
	if len(required) > 0 {
		m["required"] = required
	}
	return m
}

func str(desc string, enum ...string) map[string]any {
	m := map[string]any{"type": "string", "description": desc}
	if len(enum) > 0 {
		m["enum"] = enum
	}
	return m
}

func argStr(a map[string]any, k string) string {
	if v, ok := a[k].(string); ok {
		return v
	}
	return ""
}

func argInt(a map[string]any, k string, def int) int {
	switch v := a[k].(type) {
	case float64:
		return int(v)
	case int:
		return v
	case string:
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

func argStrings(a map[string]any, k string) []string {
	var out []string
	switch v := a[k].(type) {
	case []any:
		for _, x := range v {
			if s, ok := x.(string); ok {
				out = append(out, s)
			}
		}
	case string:
		out = strings.Fields(v)
	}
	return out
}

var toolsOnce []tool

func toolTable() []tool {
	if toolsOnce != nil {
		return toolsOnce
	}
	toolsOnce = []tool{
		{Name: "system_info", Title: "System information", Cap: "system.read", ReadOnly: true,
			Description: "KwickOS version and edition, kernel, architecture, CPU, memory, disk, desktop session and which kwick-* tools exist.",
			fn:          toolSystemInfo},
		{Name: "permissions_get", Title: "My permissions", Cap: "system.read", ReadOnly: true,
			Description: "Which capabilities this agent has (allow, ask or deny), which folders it may use and whether it runs in a sandbox.",
			fn:          toolPermissions},
		{Name: "packages_installed", Title: "Installed packages", Cap: "system.read", ReadOnly: true,
			Description: "Installed Debian packages with versions. Optional shell-style pattern such as 'linux-image*' or 'python3'.",
			Schema:      obj(map[string]any{"pattern": str("Package name or glob; empty lists everything (first 500)")}),
			fn:          toolPkgInstalled},
		{Name: "packages_search", Title: "Search packages", Cap: "system.read", ReadOnly: true,
			Description: "Search the configured apt repositories (KwickOS and Debian 13) by name and description.",
			Schema:      obj(map[string]any{"query": str("Words to search for")}, "query"),
			fn:          toolPkgSearch},
		{Name: "packages_updates", Title: "Available updates", Cap: "system.read", ReadOnly: true,
			Description: "Result of the last update check from kwick-update (system packages, apps, kernels, settings).",
			fn:          toolUpdates},
		{Name: "packages_install", Title: "Install packages", Cap: "packages.manage", Destructive: false,
			Description: "Install Debian packages with apt. The user approves the request and an administrator password is asked.",
			Schema:      obj(map[string]any{"packages": map[string]any{"type": "array", "items": map[string]any{"type": "string"}, "minItems": 1, "maxItems": 20}}, "packages"),
			fn:          toolPkgInstall, detail: func(s *Server, a map[string]any) string {
				return "Install packages: " + strings.Join(argStrings(a, "packages"), " ")
			}, precheck: func(s *Server, a map[string]any) error { return validPkgs(argStrings(a, "packages")) }},
		{Name: "system_upgrade", Title: "Install system updates", Cap: "packages.manage", Destructive: true,
			Description: "Install pending updates with kwick-update (a new kernel is tried once before it becomes the default).",
			Schema:      obj(map[string]any{"scope": str("What to update", "all", "system", "apps", "security")}),
			fn:          toolUpgrade, detail: func(s *Server, a map[string]any) string {
				sc := argStr(a, "scope")
				if sc == "" {
					sc = "all"
				}
				return "Install updates (" + sc + ")"
			}},
		{Name: "snapshots_list", Title: "List snapshots", Cap: "system.read", ReadOnly: true,
			Description: "System snapshots from kwick-snapshot, when it is installed.",
			fn:          toolSnapList},
		{Name: "snapshots_create", Title: "Create a snapshot", Cap: "snapshots.manage",
			Description: "Create a system snapshot with kwick-snapshot before a risky change.",
			Schema:      obj(map[string]any{"description": str("Why the snapshot is taken")}),
			fn:          toolSnapCreate, detail: func(s *Server, a map[string]any) string {
				return "Create a system snapshot: " + argStr(a, "description")
			}},
		{Name: "files_list", Title: "List a folder", Cap: "files.read", ReadOnly: true,
			Description: "List a folder inside the project folder or a granted folder.",
			Schema:      obj(map[string]any{"path": str("Folder path; relative paths start at the project folder")}),
			fn:          toolFilesList, detail: pathDetail},
		{Name: "files_read", Title: "Read a file", Cap: "files.read", ReadOnly: true,
			Description: "Read a text file inside the project folder or a granted folder (up to 1 MB per call).",
			Schema: obj(map[string]any{"path": str("File path"), "offset": map[string]any{"type": "integer", "minimum": 0},
				"max_bytes": map[string]any{"type": "integer", "minimum": 1, "maximum": 1048576}}, "path"),
			fn: toolFilesRead, detail: pathDetail},
		{Name: "files_write", Title: "Write a file", Cap: "files.write", Destructive: true,
			Description: "Create, overwrite or append to a file inside the project folder or a granted folder.",
			Schema: obj(map[string]any{"path": str("File path"), "content": str("Text to write"),
				"mode": str("create fails if the file exists", "create", "overwrite", "append")}, "path", "content"),
			fn: toolFilesWrite, detail: func(s *Server, a map[string]any) string {
				m := argStr(a, "mode")
				if m == "" {
					m = "overwrite"
				}
				return fmt.Sprintf("%s %s (%s)", strings.Title(m), argStr(a, "path"), humanBytes(int64(len(argStr(a, "content")))))
			}, precheck: func(s *Server, a map[string]any) error {
				_, err := s.resolveWrite(argStr(a, "path"))
				return err
			}},
		{Name: "notify", Title: "Desktop notification", Cap: "notify",
			Description: "Show a desktop notification to the user.",
			Schema:      obj(map[string]any{"title": str("Short title"), "body": str("Message"), "urgency": str("Urgency", "low", "normal", "critical")}, "title"),
			fn:          toolNotify},
		{Name: "settings_list", Title: "List settings", Cap: "system.read", ReadOnly: true,
			Description: "Every setting an agent can read and change, with its type, allowed values or range, whether it needs an administrator, whether it is available on this desktop and its current value. Filter by group (appearance, dock, effects, desktop, terminal, display, sound, notifications, network, power, touch, updates).",
			Schema: obj(map[string]any{"group": str("Only this group"), "keys": map[string]any{"type": "array", "items": map[string]any{"type": "string"}, "description": "Only these keys"},
				"values": map[string]any{"type": "boolean", "description": "Include current values (default true)"}}),
			fn: toolSettingsList},
		{Name: "settings_get", Title: "Read settings", Cap: "system.read", ReadOnly: true,
			Description: "Current values of settings by key or group (see settings_list); without arguments every setting.",
			Schema:      obj(map[string]any{"group": str("Only this group"), "keys": map[string]any{"type": "array", "items": map[string]any{"type": "string"}}}),
			fn:          toolSettingsGet},
		{Name: "settings_set", Title: "Change settings", Cap: "settings.write",
			Description: "Change one or more settings from settings_list, for example {\"settings\": {\"appearance\": \"light\", \"dock.size\": 56}}. Every value is checked against the schema first. Settings marked privileged also ask for an administrator password.",
			Schema: obj(map[string]any{"settings": map[string]any{"type": "object", "description": "key: value pairs from settings_list (at most 20)", "additionalProperties": true},
				"appearance": str("Shortcut for settings.appearance", "dark", "light"), "layout": str("Shortcut for settings.layout", "macos", "windows", "linux")}),
			fn: toolSettingsSet, precheck: settingsPrecheck, detail: settingsDetail},
		{Name: "apps_list", Title: "Installed apps", Cap: "system.read", ReadOnly: true,
			Description: "Desktop applications that can be launched, with their ids.",
			Schema:      obj(map[string]any{"query": str("Filter by name")}),
			fn:          toolAppsList},
		{Name: "apps_launch", Title: "Open an app", Cap: "apps.launch",
			Description: "Open a desktop application by its id from apps_list.",
			Schema:      obj(map[string]any{"id": str("Desktop file id, for example org.kde.dolphin.desktop")}, "id"),
			fn:          toolAppsLaunch, precheck: needApp, detail: func(s *Server, a map[string]any) string {
				id := argStr(a, "id")
				if p := findDesktop(id); p != "" {
					if n := desktopName(p); n != "" {
						return "Open " + n + " (" + id + ")"
					}
				}
				return "Open " + id
			}},
		{Name: "screenshot", Title: "Take a screenshot", Cap: "screen.capture", ReadOnly: true,
			Description: "Capture the screen, or a region of it, scaled to fit max_width x max_height (default 1280x800, good for vision models). The result says how image pixels map to desktop coordinates; pointer tools accept image pixels directly. The user is asked unless they always allow it or a computer control session is active.",
			Schema: obj(map[string]any{
				"region":     obj(map[string]any{"x": map[string]any{"type": "number"}, "y": map[string]any{"type": "number"}, "width": map[string]any{"type": "number", "minimum": 1}, "height": map[string]any{"type": "number", "minimum": 1}}, "x", "y", "width", "height"),
				"max_width":  map[string]any{"type": "integer", "minimum": 64, "maximum": 3840},
				"max_height": map[string]any{"type": "integer", "minimum": 64, "maximum": 2160},
				"format":     str("Image format (default png)", "png", "jpeg"),
				"quality":    map[string]any{"type": "integer", "minimum": 30, "maximum": 100, "description": "JPEG quality (default 85)"}}),
			fn: toolScreenshot, precheck: needGUI, detail: func(s *Server, a map[string]any) string {
				if _, ok := a["region"]; ok {
					return "Capture part of your screen and send the image to the agent"
				}
				return "Capture your whole screen and send the image to the agent"
			}},
		{Name: "agents_list", Title: "Installed agents", Cap: "system.read", ReadOnly: true,
			Description: "AI agents and runtimes known to kwick-agents and whether they are installed.",
			fn:          toolAgentsList},
	}
	toolsOnce = append(toolsOnce, computerTools()...)
	return toolsOnce
}

func readOSRelease() map[string]string {
	m := map[string]string{}
	b, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return m
	}
	for _, l := range strings.Split(string(b), "\n") {
		if i := strings.IndexByte(l, '='); i > 0 {
			m[l[:i]] = strings.Trim(l[i+1:], `"`)
		}
	}
	return m
}

func meminfo() map[string]int64 {
	m := map[string]int64{}
	f, err := os.Open("/proc/meminfo")
	if err != nil {
		return m
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		fs := strings.Fields(sc.Text())
		if len(fs) >= 2 {
			n, _ := strconv.ParseInt(fs[1], 10, 64)
			m[strings.TrimSuffix(fs[0], ":")] = n * 1024
		}
	}
	return m
}

func cpuModel() string {
	b, _ := os.ReadFile("/proc/cpuinfo")
	for _, l := range strings.Split(string(b), "\n") {
		for _, k := range []string{"model name", "uarch", "Model"} {
			if strings.HasPrefix(l, k) {
				if i := strings.IndexByte(l, ':'); i > 0 {
					return strings.TrimSpace(l[i+1:])
				}
			}
		}
	}
	return ""
}

func uts[T int8 | uint8](a [65]T) string {
	var b []byte
	for _, c := range a {
		if c == 0 {
			break
		}
		b = append(b, byte(c))
	}
	return string(b)
}

func runJSON(timeout time.Duration, name string, args ...string) (json.RawMessage, error) {
	if lookPath(name) == "" {
		return nil, fmt.Errorf("%s is not installed", name)
	}
	out, err := runTimeout(timeout, name, args...)
	if err != nil {
		return nil, fmt.Errorf("%s %s: %v %s", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	out = bytes.TrimSpace(out)
	if !json.Valid(out) {
		return nil, fmt.Errorf("%s did not print JSON", name)
	}
	return json.RawMessage(out), nil
}

func runTimeout(timeout time.Duration, name string, args ...string) ([]byte, error) {
	c := exec.Command(name, args...)
	var buf bytes.Buffer
	c.Stdout = &buf
	c.Stderr = &buf
	if err := c.Start(); err != nil {
		return nil, err
	}
	done := make(chan error, 1)
	go func() { done <- c.Wait() }()
	select {
	case err := <-done:
		return buf.Bytes(), err
	case <-time.After(timeout):
		c.Process.Kill()
		return buf.Bytes(), fmt.Errorf("timed out after %s", timeout)
	}
}

func edition() string {
	if exists("/usr/bin/kwick-settings") || exists("/usr/share/kwick/settings/Main.qml") {
		return "desktop"
	}
	return "headless"
}

func toolSystemInfo(s *Server, a map[string]any) (toolResult, error) {
	osr := readOSRelease()
	var u syscall.Utsname
	syscall.Uname(&u)
	var sf syscall.Statfs_t
	syscall.Statfs("/", &sf)
	mi := meminfo()
	up := ""
	if b, err := os.ReadFile("/proc/uptime"); err == nil {
		if f := strings.Fields(string(b)); len(f) > 0 {
			if v, err := strconv.ParseFloat(f[0], 64); err == nil {
				up = (time.Duration(v) * time.Second).String()
			}
		}
	}
	rel, _ := os.ReadFile("/etc/kwick-release")
	host, _ := os.Hostname()
	var tools []string
	for _, d := range []string{"/usr/bin", "/usr/sbin"} {
		ms, _ := filepath.Glob(filepath.Join(d, "kwick-*"))
		for _, m := range ms {
			tools = append(tools, filepath.Base(m))
		}
	}
	sort.Strings(tools)
	data := map[string]any{
		"os":                osr["PRETTY_NAME"],
		"os_id":             osr["ID"],
		"version":           osr["VERSION_ID"],
		"kwick":             strings.TrimSpace(string(rel)),
		"edition":           edition(),
		"debian_compatible": "13 (trixie)",
		"kernel":            uts(u.Release),
		"arch":              hostArch(),
		"machine":           uts(u.Machine),
		"hostname":          host,
		"cpu":               cpuModel(),
		"cpus":              runtime.NumCPU(),
		"memory_total":      mi["MemTotal"],
		"memory_available":  mi["MemAvailable"],
		"disk_root_total":   int64(sf.Blocks) * int64(sf.Bsize),
		"disk_root_free":    int64(sf.Bavail) * int64(sf.Bsize),
		"uptime":            up,
		"desktop":           os.Getenv("XDG_CURRENT_DESKTOP"),
		"session_type":      os.Getenv("XDG_SESSION_TYPE"),
		"package_manager":   "kpkg (apt and dpkg compatible); use packages_* tools",
		"init":              "kinit",
		"kwick_tools":       tools,
		"agent":             s.agent,
		"sandboxed":         s.sandboxed,
	}
	if k, err := runJSON(10*time.Second, "kwick-kernel", "status", "--json"); err == nil {
		data["kernel_status"] = k
	}
	return toolResult{Data: data}, nil
}

func toolPermissions(s *Server, a map[string]any) (toolResult, error) {
	return toolResult{Data: map[string]any{
		"agent":        s.agent,
		"client":       s.client,
		"sandboxed":    s.sandboxed,
		"capabilities": effectiveGrants(loadGrants(), s.agent),
		"folders":      s.allowedRoots(),
		"descriptions": capabilities,
	}}, nil
}

type dpkgPkg struct {
	Name    string `json:"name"`
	Version string `json:"version"`
	Arch    string `json:"arch"`
	Summary string `json:"summary"`
}

func installedPackages() []dpkgPkg {
	f, err := os.Open("/var/lib/dpkg/status")
	if err != nil {
		return nil
	}
	defer f.Close()
	var out []dpkgPkg
	var cur dpkgPkg
	installed := false
	flush := func() {
		if cur.Name != "" && installed {
			out = append(out, cur)
		}
		cur = dpkgPkg{}
		installed = false
	}
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 4<<20)
	for sc.Scan() {
		l := sc.Text()
		if l == "" {
			flush()
			continue
		}
		switch {
		case strings.HasPrefix(l, "Package: "):
			cur.Name = l[9:]
		case strings.HasPrefix(l, "Version: "):
			cur.Version = l[9:]
		case strings.HasPrefix(l, "Architecture: "):
			cur.Arch = l[14:]
		case strings.HasPrefix(l, "Status: "):
			installed = strings.HasSuffix(l, " installed")
		case strings.HasPrefix(l, "Description: "):
			cur.Summary = l[13:]
		}
	}
	flush()
	return out
}

func toolPkgInstalled(s *Server, a map[string]any) (toolResult, error) {
	pat := argStr(a, "pattern")
	var out []dpkgPkg
	for _, p := range installedPackages() {
		if pat != "" {
			if ok, _ := filepath.Match(pat, p.Name); !ok && !strings.Contains(p.Name, pat) {
				continue
			}
		}
		out = append(out, p)
	}
	total := len(out)
	if len(out) > 500 {
		out = out[:500]
	}
	if out == nil {
		out = []dpkgPkg{}
	}
	return toolResult{Data: map[string]any{"count": total, "packages": out, "truncated": total > len(out)}}, nil
}

var pkgRe = regexp.MustCompile(`^[a-z0-9][a-z0-9+.-]{0,99}(:[a-z0-9]+)?(=[A-Za-z0-9.+~:-]+)?$`)

func validPkgs(p []string) error {
	if len(p) == 0 {
		return fmt.Errorf("packages is empty")
	}
	if len(p) > 20 {
		return fmt.Errorf("at most 20 packages per request")
	}
	for _, x := range p {
		if !pkgRe.MatchString(x) {
			return fmt.Errorf("%q is not a valid package name", x)
		}
	}
	return nil
}

func toolPkgSearch(s *Server, a map[string]any) (toolResult, error) {
	q := strings.Fields(argStr(a, "query"))
	if len(q) == 0 {
		return toolResult{}, fmt.Errorf("query is empty")
	}
	for _, w := range q {
		if strings.HasPrefix(w, "-") {
			return toolResult{}, fmt.Errorf("invalid query")
		}
	}
	out, err := runTimeout(60*time.Second, "apt-cache", append([]string{"search", "--"}, q...)...)
	if err != nil {
		out, err = runTimeout(60*time.Second, "apt-cache", append([]string{"search"}, q...)...)
	}
	if err != nil {
		return toolResult{}, fmt.Errorf("apt-cache search failed: %v %s", err, strings.TrimSpace(string(out)))
	}
	type hit struct {
		Name    string `json:"name"`
		Summary string `json:"summary"`
	}
	var hits []hit
	for _, l := range strings.Split(string(out), "\n") {
		if i := strings.Index(l, " - "); i > 0 {
			hits = append(hits, hit{l[:i], l[i+3:]})
		}
	}
	total := len(hits)
	if len(hits) > 100 {
		hits = hits[:100]
	}
	if hits == nil {
		hits = []hit{}
	}
	return toolResult{Data: map[string]any{"count": total, "results": hits, "truncated": total > len(hits)}}, nil
}

func toolUpdates(s *Server, a map[string]any) (toolResult, error) {
	j, err := runJSON(30*time.Second, "kwick-update", "status", "--json")
	if err != nil {
		return toolResult{}, err
	}
	var v any
	json.Unmarshal(j, &v)
	return toolResult{Data: v}, nil
}

func runPrivileged(agent string, args ...string) (string, error) {
	if !exists(privHelper) {
		return "", fmt.Errorf("%s is missing", privHelper)
	}
	full := append([]string{privHelper, "--agent", agent}, args...)
	var c *exec.Cmd
	switch {
	case isRoot():
		c = exec.Command(full[0], full[1:]...)
	case guiEnv() && lookPath("pkexec") != "":
		c = exec.Command("pkexec", full...)
	case lookPath("sudo") != "" && exec.Command("sudo", "-n", "true").Run() == nil:
		c = exec.Command("sudo", append([]string{"-n"}, full...)...)
	default:
		return "", fmt.Errorf("this needs an administrator and no password prompt is available here (no desktop session). Ask the user to run: sudo %s", userCommand(args))
	}
	var buf bytes.Buffer
	c.Stdout = &buf
	c.Stderr = &buf
	err := c.Run()
	out := buf.String()
	if len(out) > 20000 {
		out = "..." + out[len(out)-20000:]
	}
	if err != nil {
		code := exitCode(err)
		if code == 126 || code == 127 {
			return out, fmt.Errorf("the administrator password prompt was dismissed or failed")
		}
		return out, fmt.Errorf("failed (exit %d): %s", code, strings.TrimSpace(out))
	}
	return out, nil
}

func toolPkgInstall(s *Server, a map[string]any) (toolResult, error) {
	p := argStrings(a, "packages")
	out, err := runPrivileged(s.agent, append([]string{"install"}, p...)...)
	if err != nil {
		return toolResult{}, err
	}
	return toolResult{Text: out, Data: map[string]any{"installed": p, "log": out}}, nil
}

func toolUpgrade(s *Server, a map[string]any) (toolResult, error) {
	sc := argStr(a, "scope")
	if sc == "" {
		sc = "all"
	}
	switch sc {
	case "all", "system", "apps", "security":
	default:
		return toolResult{}, fmt.Errorf("scope must be all, system, apps or security")
	}
	out, err := runPrivileged(s.agent, "upgrade", sc)
	if err != nil {
		return toolResult{}, err
	}
	return toolResult{Data: map[string]any{"scope": sc, "log": out}}, nil
}

func toolSnapList(s *Server, a map[string]any) (toolResult, error) {
	j, err := runJSON(30*time.Second, "kwick-snapshot", "list", "--json")
	if err != nil {
		return toolResult{}, err
	}
	var v any
	json.Unmarshal(j, &v)
	return toolResult{Data: v}, nil
}

func toolSnapCreate(s *Server, a map[string]any) (toolResult, error) {
	if lookPath("kwick-snapshot") == "" {
		return toolResult{}, fmt.Errorf("kwick-snapshot is not installed")
	}
	d := argStr(a, "description")
	if d == "" {
		d = "before a change by " + s.agent
	}
	d = strings.Map(func(r rune) rune {
		if r < 32 || r == 127 {
			return -1
		}
		return r
	}, d)
	if len(d) > 200 {
		d = d[:200]
	}
	out, err := runPrivileged(s.agent, "snapshot", d)
	if err != nil {
		return toolResult{}, err
	}
	return toolResult{Data: map[string]any{"description": d, "log": out}}, nil
}

func toolFilesList(s *Server, a map[string]any) (toolResult, error) {
	p := argStr(a, "path")
	if p == "" {
		if len(s.roots) == 0 {
			return toolResult{Data: map[string]any{"folders": s.allowedRoots()}}, nil
		}
		p = s.roots[0]
	}
	rp, err := s.resolvePath(p, true)
	if err != nil {
		return toolResult{}, err
	}
	d, err := s.openRead(rp)
	if err != nil {
		return toolResult{}, err
	}
	ents, err := d.ReadDir(-1)
	d.Close()
	if err != nil {
		return toolResult{}, err
	}
	sort.Slice(ents, func(i, j int) bool { return ents[i].Name() < ents[j].Name() })
	type ent struct {
		Name     string `json:"name"`
		Type     string `json:"type"`
		Size     int64  `json:"size"`
		Modified string `json:"modified"`
	}
	var out []ent
	for i, e := range ents {
		if i >= 1000 {
			break
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		t := "file"
		if e.IsDir() {
			t = "dir"
		} else if info.Mode()&os.ModeSymlink != 0 {
			t = "symlink"
		}
		out = append(out, ent{e.Name(), t, info.Size(), info.ModTime().UTC().Format(time.RFC3339)})
	}
	if out == nil {
		out = []ent{}
	}
	return toolResult{Data: map[string]any{"path": rp, "entries": out, "truncated": len(ents) > 1000}}, nil
}

func toolFilesRead(s *Server, a map[string]any) (toolResult, error) {
	rp, err := s.resolvePath(argStr(a, "path"), true)
	if err != nil {
		return toolResult{}, err
	}
	f, err := s.openRead(rp)
	if err != nil {
		return toolResult{}, err
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return toolResult{}, err
	}
	if st.IsDir() {
		return toolResult{}, fmt.Errorf("%s is a folder; use files_list", rp)
	}
	max := argInt(a, "max_bytes", 262144)
	if max <= 0 || max > 1<<20 {
		max = 1 << 20
	}
	off := int64(argInt(a, "offset", 0))
	if off > 0 {
		f.Seek(off, 0)
	}
	buf := make([]byte, max)
	n, _ := f.Read(buf)
	buf = buf[:n]
	if bytes.IndexByte(buf, 0) >= 0 || !utf8.Valid(buf) {
		return toolResult{Data: map[string]any{"path": rp, "size": st.Size(), "binary": true}, Text: fmt.Sprintf("%s is a binary file (%s)", rp, humanBytes(st.Size()))}, nil
	}
	more := off+int64(n) < st.Size()
	return toolResult{Text: string(buf), Data: map[string]any{"path": rp, "size": st.Size(), "offset": off, "bytes": n, "more": more}}, nil
}

func toolFilesWrite(s *Server, a map[string]any) (toolResult, error) {
	rp, err := s.resolveWrite(argStr(a, "path"))
	if err != nil {
		return toolResult{}, err
	}
	content := argStr(a, "content")
	if len(content) > 5<<20 {
		return toolResult{}, fmt.Errorf("content is larger than 5 MB")
	}
	mode := argStr(a, "mode")
	switch mode {
	case "", "overwrite":
		mode = "overwrite"
	case "create", "append":
	default:
		return toolResult{}, fmt.Errorf("mode must be create, overwrite or append")
	}
	n, err := s.writeFile(rp, mode, content)
	if err != nil {
		return toolResult{}, err
	}
	return toolResult{Data: map[string]any{"path": rp, "bytes": n, "mode": mode}}, nil
}

func toolNotify(s *Server, a map[string]any) (toolResult, error) {
	title := argStr(a, "title")
	body := argStr(a, "body")
	urg := argStr(a, "urgency")
	if urg == "" {
		urg = "normal"
	}
	if len(title) > 200 {
		title = title[:200]
	}
	if len(body) > 2000 {
		body = body[:2000]
	}
	if guiEnv() && lookPath("notify-send") != "" {
		c := exec.Command("notify-send", "--app-name="+s.agent, "--urgency="+urg, "--icon=dialog-information", "--", title, body)
		if out, err := c.CombinedOutput(); err != nil {
			return toolResult{}, fmt.Errorf("notify-send: %v %s", err, strings.TrimSpace(string(out)))
		}
		return toolResult{Data: map[string]any{"delivered": true, "via": "notify-send"}}, nil
	}
	return toolResult{Data: map[string]any{"delivered": false, "via": "audit log", "note": "no desktop session; the message is only in the audit log"}}, nil
}

func desktopDirs() []string {
	dd := os.Getenv("XDG_DATA_DIRS")
	if dd == "" {
		dd = "/usr/local/share:/usr/share"
	}
	dirs := []string{filepath.Join(xdg("XDG_DATA_HOME", ".local/share"), "applications")}
	for _, d := range strings.Split(dd, ":") {
		if d != "" {
			dirs = append(dirs, filepath.Join(d, "applications"))
		}
	}
	dirs = append(dirs, "/var/lib/flatpak/exports/share/applications")
	return dirs
}

func parseDesktop(p string) map[string]string {
	m := map[string]string{}
	f, err := os.Open(p)
	if err != nil {
		return m
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	in := false
	for sc.Scan() {
		l := strings.TrimSpace(sc.Text())
		if strings.HasPrefix(l, "[") {
			in = l == "[Desktop Entry]"
			continue
		}
		if !in {
			continue
		}
		if i := strings.IndexByte(l, '='); i > 0 {
			k := strings.TrimSpace(l[:i])
			if _, ok := m[k]; !ok {
				m[k] = strings.TrimSpace(l[i+1:])
			}
		}
	}
	return m
}

func desktopName(p string) string { return parseDesktop(p)["Name"] }

var desktopIDRe = regexp.MustCompile(`^[A-Za-z0-9._-]+\.desktop$`)

func findDesktop(id string) string {
	if !desktopIDRe.MatchString(id) {
		return ""
	}
	for _, d := range desktopDirs() {
		p := filepath.Join(d, id)
		if exists(p) {
			return p
		}
	}
	return ""
}

func toolAppsList(s *Server, a map[string]any) (toolResult, error) {
	q := strings.ToLower(argStr(a, "query"))
	type app struct {
		ID      string `json:"id"`
		Name    string `json:"name"`
		Comment string `json:"comment,omitempty"`
	}
	seen := map[string]bool{}
	var out []app
	for _, d := range desktopDirs() {
		ms, _ := filepath.Glob(filepath.Join(d, "*.desktop"))
		for _, p := range ms {
			id := filepath.Base(p)
			if seen[id] {
				continue
			}
			seen[id] = true
			m := parseDesktop(p)
			if m["Type"] != "Application" || m["NoDisplay"] == "true" || m["Hidden"] == "true" || m["Name"] == "" {
				continue
			}
			if q != "" && !strings.Contains(strings.ToLower(m["Name"]+" "+id+" "+m["Comment"]+" "+m["Keywords"]), q) {
				continue
			}
			out = append(out, app{id, m["Name"], m["Comment"]})
		}
	}
	sort.Slice(out, func(i, j int) bool { return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name) })
	if out == nil {
		out = []app{}
	}
	return toolResult{Data: map[string]any{"count": len(out), "apps": out}}, nil
}

func toolAppsLaunch(s *Server, a map[string]any) (toolResult, error) {
	id := argStr(a, "id")
	p := findDesktop(id)
	if p == "" {
		return toolResult{}, fmt.Errorf("no application with id %q (see apps_list)", id)
	}
	if !guiEnv() {
		return toolResult{}, fmt.Errorf("no desktop session to open %s in", id)
	}
	var c *exec.Cmd
	switch {
	case lookPath("gtk-launch") != "":
		c = exec.Command("gtk-launch", strings.TrimSuffix(id, ".desktop"))
	case lookPath("kioclient") != "":
		c = exec.Command("kioclient", "exec", p)
	case lookPath("gio") != "":
		c = exec.Command("gio", "launch", p)
	case lookPath("kstart") != "":
		c = exec.Command("kstart", "--application", strings.TrimSuffix(id, ".desktop"))
	default:
		return toolResult{}, fmt.Errorf("no launcher found (gtk-launch, kioclient, gio or kstart)")
	}
	c.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	c.Stdin, c.Stdout, c.Stderr = nil, nil, nil
	if err := c.Start(); err != nil {
		return toolResult{}, err
	}
	go c.Wait()
	return toolResult{Data: map[string]any{"launched": id, "name": desktopName(p)}}, nil
}

func captureScreen() (image.Image, string, error) {
	if !guiEnv() {
		return nil, "", fmt.Errorf("no desktop session to capture")
	}
	var kwinErr error
	if desktopKind() == "kde" {
		img, err := kwinScreenshot()
		if err == nil {
			return img, "KWin ScreenShot2", nil
		}
		kwinErr = err
	}
	rd := runtimeDir()
	os.MkdirAll(rd, 0o700)
	f := filepath.Join(rd, fmt.Sprintf("shot-%d.png", time.Now().UnixNano()))
	defer os.Remove(f)
	dk := desktopKind()
	type cand struct {
		ok   bool
		name string
		args []string
	}
	cands := []cand{
		{dk == "kde", "spectacle", []string{"-b", "-n", "-f", "-o", f}},
		{dk == "hyprland" || dk == "sway", "grim", []string{f}},
		{dk == "gnome", "gnome-screenshot", []string{"-f", f}},
		{true, "spectacle", []string{"-b", "-n", "-f", "-o", f}},
		{os.Getenv("WAYLAND_DISPLAY") != "", "grim", []string{f}},
		{os.Getenv("DISPLAY") != "" && os.Getenv("WAYLAND_DISPLAY") == "", "import", []string{"-window", "root", f}},
	}
	var errs []string
	tried := map[string]bool{}
	for _, c := range cands {
		if !c.ok || lookPath(c.name) == "" || tried[c.name] {
			continue
		}
		tried[c.name] = true
		out, err := runTimeout(30*time.Second, c.name, c.args...)
		if exists(f) {
			b, rerr := os.ReadFile(f)
			if rerr == nil && len(b) > 0 {
				img, derr := png.Decode(bytes.NewReader(b))
				if derr == nil {
					return img, c.name, nil
				}
				err = derr
			}
		}
		errs = append(errs, fmt.Sprintf("%s: %v %s", c.name, err, strings.TrimSpace(string(out))))
	}
	if kwinErr != nil {
		errs = append([]string{"KWin: " + kwinErr.Error()}, errs...)
	}
	if len(errs) == 0 {
		return nil, "", fmt.Errorf("no screenshot tool found (spectacle, grim or gnome-screenshot)")
	}
	return nil, "", fmt.Errorf("screenshot failed: %s", strings.Join(errs, "; "))
}

func toolScreenshot(s *Server, a map[string]any) (toolResult, error) {
	maxW, maxH := argInt(a, "max_width", 1280), argInt(a, "max_height", 800)
	if maxW < 64 || maxW > 3840 || maxH < 64 || maxH > 2160 {
		return toolResult{}, fmt.Errorf("max_width must be 64-3840 and max_height 64-2160")
	}
	format := argStr(a, "format")
	if format == "" {
		format = "png"
	}
	if format != "png" && format != "jpeg" {
		return toolResult{}, fmt.Errorf("format must be png or jpeg")
	}
	var region *rectF
	if r, ok := a["region"].(map[string]any); ok {
		x, ox := argNum(r, "x")
		y, oy := argNum(r, "y")
		w, ow := argNum(r, "width")
		h, oh := argNum(r, "height")
		if !ox || !oy || !ow || !oh {
			return toolResult{}, fmt.Errorf("region needs x, y, width and height in desktop coordinates")
		}
		region = &rectF{x, y, w, h}
	}
	raw, via, err := captureScreen()
	if err != nil {
		return toolResult{}, err
	}
	var desk rectF
	sc, serr := s.screens()
	if serr == nil {
		desk = desktopRect(sc)
	}
	img, mime, g, err := processShot(raw, desk, region, maxW, maxH, format, argInt(a, "quality", 85))
	if err != nil {
		return toolResult{}, err
	}
	s.shared.setShot(g)
	data := map[string]any{"width": g.Width, "height": g.Height, "format": strings.TrimPrefix(mime, "image/"), "bytes": len(img), "via": via,
		"origin_x": g.OriginX, "origin_y": g.OriginY, "scale": g.Scale,
		"mapping": fmt.Sprintf("desktop_x = %.4g + image_x * %.4g, desktop_y = %.4g + image_y * %.4g; pointer tools use image pixels by default", g.OriginX, g.Scale, g.OriginY, g.Scale)}
	if serr == nil {
		data["desktop"] = map[string]any{"x": desk.X, "y": desk.Y, "width": desk.W, "height": desk.H}
	}
	return toolResult{Image: img, Mime: mime, Data: data, Text: fmt.Sprintf("Screenshot %dx%d %s (1 image pixel = %.3g desktop pixels, origin %.0f,%.0f). Pointer tools take x,y in these image pixels.", g.Width, g.Height, strings.TrimPrefix(mime, "image/"), g.Scale, g.OriginX, g.OriginY)}, nil
}

func toolAgentsList(s *Server, a map[string]any) (toolResult, error) {
	c, err := loadCatalog()
	if err != nil {
		return toolResult{}, err
	}
	var items []ListItem
	for _, e := range c.Entries {
		if !e.Hidden {
			items = append(items, listItem(c, e, hostArch()))
		}
	}
	return toolResult{Data: map[string]any{"agents": items}}, nil
}

func needGUI(s *Server, a map[string]any) error {
	if !guiEnv() {
		return fmt.Errorf("no desktop session here (headless, or the agent was not started from a desktop session)")
	}
	return nil
}

func needApp(s *Server, a map[string]any) error {
	if findDesktop(argStr(a, "id")) == "" {
		return fmt.Errorf("no application with id %q (see apps_list)", argStr(a, "id"))
	}
	return needGUI(s, a)
}

func pathDetail(s *Server, a map[string]any) string {
	p := argStr(a, "path")
	if p == "" {
		return "project folder"
	}
	return p
}

func userCommand(args []string) string {
	if len(args) == 0 {
		return ""
	}
	switch args[0] {
	case "install":
		return "apt install " + strings.Join(args[1:], " ")
	case "upgrade":
		return "kwick-update upgrade " + strings.Join(args[1:], " ")
	case "snapshot":
		return "kwick-snapshot create '" + strings.Join(args[1:], " ") + "'"
	case "session":
		return "kwick-desktop switch " + strings.Join(args[1:], " ")
	case "login-shell":
		return "kwick-shell " + strings.Join(args[1:], " ")
	case "auto-update":
		if len(args) == 3 && args[1] == "interval" {
			return "kwick-update auto interval " + args[2]
		}
		return "kwick-update auto set " + strings.Join(args[1:], " ")
	}
	return strings.Join(args, " ")
}
