package main

import (
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

type Profile struct {
	Sandbox bool              `json:"sandbox"`
	Network bool              `json:"network"`
	GPU     bool              `json:"gpu"`
	Project bool              `json:"project"`
	RW      []string          `json:"rw"`
	RO      []string          `json:"ro"`
	Env     map[string]string `json:"env,omitempty"`
}

type profileFile struct {
	Sandbox *bool             `json:"sandbox,omitempty"`
	Network *bool             `json:"network,omitempty"`
	GPU     *bool             `json:"gpu,omitempty"`
	Project *bool             `json:"project,omitempty"`
	RW      []string          `json:"rw,omitempty"`
	RO      []string          `json:"ro,omitempty"`
	Env     map[string]string `json:"env,omitempty"`
}

func profilePath(sc Scope, name string) string {
	return filepath.Join(sc.Config, "agents", name+".json")
}

func effectiveProfile(e *Entry) Profile {
	p := Profile{Sandbox: true, Network: e.Network, GPU: e.GPU, Project: true, RW: []string{}, RO: []string{}}
	for _, sc := range []Scope{systemScope(), userScope()} {
		var f profileFile
		if readJSONFile(profilePath(sc, e.Name), &f) != nil {
			continue
		}
		if f.Sandbox != nil {
			p.Sandbox = *f.Sandbox
		}
		if f.Network != nil {
			p.Network = *f.Network
		}
		if f.GPU != nil {
			p.GPU = *f.GPU
		}
		if f.Project != nil {
			p.Project = *f.Project
		}
		p.RW = append(p.RW, f.RW...)
		p.RO = append(p.RO, f.RO...)
		for k, v := range f.Env {
			if p.Env == nil {
				p.Env = map[string]string{}
			}
			p.Env[k] = v
		}
	}
	return p
}

func cmdProfileToggle(o opts, pos []string, key string) error {
	if len(pos) < 1 || len(pos) > 2 {
		return fmt.Errorf("usage: kwick-agents %s NAME [on|off]", key)
	}
	c, err := loadCatalog()
	if err != nil {
		return err
	}
	e, err := c.get(pos[0])
	if err != nil {
		return err
	}
	if len(pos) == 1 {
		p := effectiveProfile(e)
		v := p.Sandbox
		if key == "network" {
			v = p.Network
		}
		if o.json {
			emitJSON(map[string]any{"name": e.Name, key: v})
		} else if v {
			fmt.Println("on")
		} else {
			fmt.Println("off")
		}
		return nil
	}
	var v bool
	switch pos[1] {
	case "on", "true", "yes":
		v = true
	case "off", "false", "no":
		v = false
	default:
		return fmt.Errorf("usage: kwick-agents %s NAME [on|off]", key)
	}
	sc := userScope()
	if isRoot() && o.system {
		sc = systemScope()
	}
	var f profileFile
	readJSONFile(profilePath(sc, e.Name), &f)
	if key == "sandbox" {
		f.Sandbox = &v
	} else {
		f.Network = &v
	}
	if err := writeJSONFile(profilePath(sc, e.Name), f, 0o644); err != nil {
		return err
	}
	auditLog(auditEntry{Agent: e.Name, Tool: "cli", Capability: key, Decision: pos[1], OK: true, Summary: "kwick-agents " + key + " " + e.Name + " " + pos[1]})
	if key == "sandbox" && !v {
		say("%s now runs without the bubblewrap sandbox: it can read and change everything your user account can.", e.Name)
	}
	return nil
}

func expandHome(p string) string {
	if p == "~" {
		return homeDir()
	}
	if strings.HasPrefix(p, "~/") {
		return filepath.Join(homeDir(), p[2:])
	}
	return p
}

var passEnv = []string{"TERM", "COLORTERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "LANG", "LANGUAGE", "LC_ALL", "LC_CTYPE", "LC_MESSAGES", "LC_NUMERIC", "LC_TIME", "LC_COLLATE", "LC_MONETARY", "TZ", "EDITOR", "VISUAL", "PAGER", "NO_COLOR", "FORCE_COLOR", "CLICOLOR", "http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY", "no_proxy", "NO_PROXY", "ALL_PROXY", "SSL_CERT_FILE", "SSL_CERT_DIR", "COLUMNS", "LINES"}

func agentEnv(e *Entry, in *Installed, rt *Installed, prof Profile, sandboxed bool, sock string) []string {
	m := map[string]string{}
	if sandboxed {
		for _, k := range passEnv {
			if v, ok := os.LookupEnv(k); ok {
				m[k] = v
			}
		}
		home := homeDir()
		m["HOME"] = home
		if u := os.Getenv("USER"); u != "" {
			m["USER"] = u
			m["LOGNAME"] = u
		}
		m["SHELL"] = "/bin/sh"
		if s := os.Getenv("SHELL"); s != "" && exists(s) {
			m["SHELL"] = s
		}
		m["TMPDIR"] = "/tmp"
	} else {
		for _, kv := range os.Environ() {
			if i := strings.IndexByte(kv, '='); i > 0 {
				m[kv[:i]] = kv[i+1:]
			}
		}
	}
	var path []string
	if in.Method == "npm-lock" {
		path = append(path, filepath.Join(in.Dir, "node_modules", ".bin"))
	}
	seen := map[string]bool{}
	for _, cmd := range e.commands() {
		d := filepath.Dir(filepath.Join(in.Dir, e.Bin[cmd]))
		if !seen[d] && in.Method != "node-bundle" && in.Method != "npm-lock" {
			path = append(path, d)
			seen[d] = true
		}
	}
	if rt != nil {
		switch rt.Name {
		case "node":
			path = append(path, filepath.Join(rt.Dir, "bin"))
		default:
			path = append(path, rt.Dir)
		}
	}
	base := "/usr/local/bin:/usr/bin:/bin"
	if !sandboxed && m["PATH"] != "" {
		base = m["PATH"]
	}
	m["PATH"] = strings.Join(append(path, base), ":")
	for k, v := range e.Env {
		m[k] = v
	}
	for k, v := range prof.Env {
		m[k] = v
	}
	m["KWICK_AGENT"] = e.Name
	if sandboxed {
		m["KWICK_AGENT_SANDBOX"] = "1"
	} else {
		m["KWICK_AGENT_SANDBOX"] = "0"
	}
	if sock != "" {
		m["KWICK_MCP_SOCKET"] = sock
	}
	for k, v := range loadSecretsFor(e.Name) {
		m[k] = v
	}
	applyLocalRun(e, m)
	out := make([]string, 0, len(m))
	for k, v := range m {
		out = append(out, k+"="+v)
	}
	sort.Strings(out)
	return out
}

func privateHome(name string) string {
	return filepath.Join(userScope().Data, "home", name)
}

func projectOK(cwd string) bool {
	home := homeDir()
	if cwd == "" || cwd == "/" || cwd == home {
		return false
	}
	for _, p := range []string{"/usr", "/etc", "/bin", "/sbin", "/lib", "/boot", "/proc", "/sys", "/dev", "/run", "/var/lib", "/root", "/opt/kwick-agents"} {
		if cwd == p || strings.HasPrefix(cwd, p+"/") {
			return home == "/root" && strings.HasPrefix(cwd, "/root/")
		}
	}
	if cwd == "/home" || cwd == filepath.Dir(home) {
		return false
	}
	return true
}

func ensureHomePath(p string, dir bool) {
	if exists(p) {
		return
	}
	if dir {
		os.MkdirAll(p, 0o700)
		return
	}
	os.MkdirAll(filepath.Dir(p), 0o700)
	content := []byte{}
	if strings.HasSuffix(p, ".json") {
		content = []byte("{}\n")
	}
	os.WriteFile(p, content, 0o600)
}

func bwrapArgs(e *Entry, in *Installed, rt *Installed, prof Profile, network, tty bool, cwd, sock string) ([]string, string) {
	home := homeDir()
	a := []string{"--die-with-parent", "--unshare-all"}
	if network {
		a = append(a, "--share-net")
	}
	if !tty {
		a = append(a, "--new-session")
	}
	a = append(a, "--ro-bind", "/usr", "/usr")
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
	a = append(a, "--ro-bind", "/etc", "/etc", "--ro-bind-try", "/opt", "/opt", "--ro-bind-try", "/sys", "/sys",
		"--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp", "--dir", "/var", "--tmpfs", "/var/tmp", "--tmpfs", "/run")
	if t, err := filepath.EvalSymlinks("/etc/resolv.conf"); err == nil && strings.HasPrefix(t, "/run/") {
		a = append(a, "--ro-bind-try", t, t)
	}
	if prof.GPU {
		a = append(a, "--dev-bind-try", "/dev/dri", "/dev/dri", "--dev-bind-try", "/dev/kfd", "/dev/kfd")
		ms, _ := filepath.Glob("/dev/nvidia*")
		for _, m := range ms {
			a = append(a, "--dev-bind-try", m, m)
		}
	}
	ph := privateHome(e.Name)
	os.MkdirAll(ph, 0o700)
	a = append(a, "--tmpfs", "/home", "--bind", ph, home)
	for _, h := range e.Home {
		dir := strings.HasSuffix(h, "/")
		p := filepath.Join(home, strings.TrimSuffix(h, "/"))
		if !dir && !strings.HasSuffix(p, ".json") && !exists(p) {
			stub := filepath.Join(ph, strings.TrimSuffix(h, "/"))
			if st, err := os.Stat(stub); err == nil && st.Mode().IsRegular() && st.Size() == 0 {
				os.Remove(stub)
			}
			continue
		}
		ensureHomePath(p, dir)
		a = append(a, "--bind", p, p)
	}
	for _, g := range []string{".gitconfig", ".config/git"} {
		a = append(a, "--ro-bind-try", filepath.Join(home, g), filepath.Join(home, g))
	}
	if !strings.HasPrefix(in.Dir, "/opt/") {
		a = append(a, "--ro-bind", in.Dir, in.Dir)
	}
	if rt != nil && !strings.HasPrefix(rt.Dir, "/opt/") {
		a = append(a, "--ro-bind", rt.Dir, rt.Dir)
	}
	if py := filepath.Join(userScope().Data, "python"); (in.Method == "uv-lock" || in.Method == "git-uv") && exists(py) {
		a = append(a, "--ro-bind", py, py)
	}
	for _, p := range prof.RO {
		p = expandHome(p)
		a = append(a, "--ro-bind-try", p, p)
	}
	for _, p := range prof.RW {
		p = expandHome(p)
		a = append(a, "--bind-try", p, p)
	}
	chdir := home
	if prof.Project && projectOK(cwd) {
		a = append(a, "--bind", cwd, cwd)
		chdir = cwd
	}
	if sock != "" {
		a = append(a, "--bind", sock, "/run/kwick-mcp.sock")
	}
	a = append(a, "--chdir", chdir)
	return a, chdir
}

func cmdRun(c *Catalog, o opts, pos []string, shell bool) int {
	if len(pos) < 1 {
		warnf("usage: kwick-agents run NAME [--cmd C] [--no-sandbox] [--offline] [-- ARGS]")
		return 2
	}
	e, err := c.get(pos[0])
	if err != nil {
		warnf("%v", err)
		return 2
	}
	args := append(append([]string{}, pos[1:]...), o.rest...)
	in, sc, ok := findInstalled(e.Name)
	if !ok {
		warnf("%s is not installed (kwick-agents install %s)", e.Name, e.Name)
		return 127
	}
	cmdName := o.cmd
	if cmdName == "" {
		cmdName = e.mainCmd()
		if e.Name != pos[0] {
			if _, ok := e.Bin[pos[0]]; ok {
				cmdName = pos[0]
			}
		}
	}
	rel, ok := e.Bin[cmdName]
	if !ok {
		warnf("%s has no command %q (commands: %s)", e.Name, cmdName, strings.Join(e.commands(), ", "))
		return 2
	}
	var rt *Installed
	if e.Runtime != "" {
		rt, err = runtimeFor(c, e, sc)
		if err != nil {
			warnf("%v", err)
			return 127
		}
	}
	target := filepath.Join(in.Dir, rel)
	if in.Legacy {
		target = filepath.Join(sysBin, "cybara")
	}
	argv := []string{target}
	if in.Method == "node-bundle" || in.Method == "npm-lock" {
		argv = []string{runtimeBin(rt, "node"), target}
	}
	if shell {
		argv = []string{"/bin/sh"}
		if len(args) > 0 {
			argv = append(argv, "-c", strings.Join(args, " "))
		}
	} else {
		argv = append(argv, args...)
	}
	prof := effectiveProfile(e)
	sandboxed := prof.Sandbox
	if o.noSandbox {
		sandboxed = false
	}
	if o.sandbox {
		sandboxed = true
	}
	network := prof.Network && !o.offline
	tty := isTerminal(0) && isTerminal(1)
	cwd, _ := os.Getwd()
	if real, err := filepath.EvalSymlinks(cwd); err == nil {
		cwd = real
	}
	roots := []string{}
	if sandboxed {
		if prof.Project && projectOK(cwd) {
			roots = append(roots, cwd)
		}
	} else if projectOK(cwd) {
		roots = append(roots, cwd)
	}
	sock, stop := startBroker(e.Name, roots, sandboxed)
	defer stop()
	innerSock := sock
	if sandboxed && sock != "" {
		innerSock = "/run/kwick-mcp.sock"
	}
	env := agentEnv(e, in, rt, prof, sandboxed, innerSock)
	var cmd *exec.Cmd
	if sandboxed {
		bw := lookPath("bwrap")
		if bw == "" {
			warnf("bubblewrap is not installed (sudo apt install bubblewrap), or run without the sandbox: kwick-agents run --no-sandbox %s", e.Name)
			return 127
		}
		ba, chdir := bwrapArgs(e, in, rt, prof, network, tty, cwd, sock)
		if chdir != cwd && prof.Project {
			fmt.Fprintf(os.Stderr, "kwick-agents: %s runs in its private home; cd into a project folder to give it that folder.\n", e.Name)
		}
		ba = append(ba, "--")
		ba = append(ba, argv...)
		cmd = exec.Command(bw, ba...)
	} else {
		cmd = exec.Command(argv[0], argv[1:]...)
		cmd.Dir = cwd
	}
	cmd.Env = env
	auditLog(auditEntry{Agent: e.Name, Tool: "run", Capability: "run", Decision: map[bool]string{true: "sandbox", false: "no-sandbox"}[sandboxed], OK: true,
		Summary: fmt.Sprintf("%s %s network=%v cwd=%s", cmdName, in.Version, network, cwd)})
	if e.MCP == "cybara" && !shell && (network || !sandboxed) && mcpConfigured(e) {
		stopAuto := make(chan struct{})
		defer close(stopAuto)
		go cybaraAutoStart(stopAuto)
	}
	if tty {
		return runWithPty(cmd)
	}
	return runPlain(cmd)
}

func startBroker(agent string, roots []string, sandboxed bool) (string, func()) {
	rd := runtimeDir()
	if err := os.MkdirAll(rd, 0o700); err != nil {
		return "", func() {}
	}
	os.Chmod(rd, 0o700)
	sock := filepath.Join(rd, fmt.Sprintf("mcp-%s-%d.sock", agent, os.Getpid()))
	os.Remove(sock)
	l, err := net.Listen("unix", sock)
	if err != nil {
		warnf("kwick-mcp broker: %v", err)
		return "", func() {}
	}
	os.Chmod(sock, 0o600)
	shared := &brokerState{agent: agent}
	go func() {
		for {
			conn, err := l.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				s := newServer(agent, roots, sandboxed)
				s.shared = shared
				s.serve(conn, conn)
			}()
		}
	}()
	return sock, func() {
		l.Close()
		os.Remove(sock)
		shared.stopControl("the agent run ended")
	}
}
