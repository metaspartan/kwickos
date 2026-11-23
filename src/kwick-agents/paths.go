package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"
)

const (
	libDir        = "/usr/lib/kwick/agents"
	sysData       = "/opt/kwick-agents"
	sysState      = "/var/lib/kwick-agents"
	sysConfig     = "/etc/kwick-agents"
	sysBin        = "/usr/local/bin"
	selfPath      = "/usr/bin/kwick-agents"
	mcpPath       = "/usr/bin/kwick-mcp"
	privHelper    = "/usr/lib/kwick/agents/kwick-agents-priv"
	agentsDocPath = "/usr/share/doc/kwickos/AGENTS.md"
)

type Scope struct {
	System bool
	Data   string
	Bin    string
	Config string
	State  string
	Home   string
}

func (s Scope) Name() string {
	if s.System {
		return "system"
	}
	return "user"
}

func isRoot() bool { return os.Geteuid() == 0 }

func homeDir() string {
	if h := os.Getenv("HOME"); h != "" {
		return h
	}
	if u, err := user.Current(); err == nil {
		return u.HomeDir
	}
	return "/root"
}

func xdg(env, def string) string {
	if v := os.Getenv(env); v != "" && filepath.IsAbs(v) {
		return v
	}
	return filepath.Join(homeDir(), def)
}

func userScope() Scope {
	return Scope{
		Data:   filepath.Join(xdg("XDG_DATA_HOME", ".local/share"), "kwick-agents"),
		Bin:    filepath.Join(homeDir(), ".local/bin"),
		Config: filepath.Join(xdg("XDG_CONFIG_HOME", ".config"), "kwick-agents"),
		State:  filepath.Join(xdg("XDG_STATE_HOME", ".local/state"), "kwick-agents"),
		Home:   homeDir(),
	}
}

func systemScope() Scope {
	return Scope{System: true, Data: sysData, Bin: sysBin, Config: sysConfig, State: sysState, Home: homeDir()}
}

func installScope(o opts) Scope {
	if o.user {
		return userScope()
	}
	if o.system || isRoot() {
		return systemScope()
	}
	return userScope()
}

func runtimeDir() string {
	if d := os.Getenv("XDG_RUNTIME_DIR"); d != "" {
		if st, err := os.Stat(d); err == nil && st.IsDir() {
			return filepath.Join(d, "kwick-agents")
		}
	}
	if d, err := os.UserCacheDir(); err == nil {
		return filepath.Join(d, "kwick-agents", "run")
	}
	return filepath.Join(os.TempDir(), fmt.Sprintf("kwick-agents-%d", os.Getuid()))
}

func hostArch() string {
	switch runtime.GOARCH {
	case "amd64", "arm64", "riscv64":
		return runtime.GOARCH
	}
	return runtime.GOARCH
}

func lookPath(name string) string {
	p, err := exec.LookPath(name)
	if err != nil {
		return ""
	}
	return p
}

func exists(p string) bool {
	_, err := os.Lstat(p)
	return err == nil
}

func writeFileAtomic(path string, data []byte, mode fs.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp := fmt.Sprintf("%s.tmp-%d", path, os.Getpid())
	if err := os.WriteFile(tmp, data, mode); err != nil {
		return err
	}
	if err := os.Chmod(tmp, mode); err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, path)
}

func writeJSONFile(path string, v any, mode fs.FileMode) error {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	return writeFileAtomic(path, append(b, '\n'), mode)
}

func readJSONFile(path string, v any) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, v)
}

func lockScope(s Scope) (func(), error) {
	if err := os.MkdirAll(s.State, 0o755); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(filepath.Join(s.State, ".lock"), os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, err
	}
	deadline := time.Now().Add(10 * time.Minute)
	for {
		err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
		if err == nil {
			break
		}
		if !errors.Is(err, syscall.EWOULDBLOCK) || time.Now().After(deadline) {
			f.Close()
			return nil, fmt.Errorf("another kwick-agents install or remove is running")
		}
		time.Sleep(300 * time.Millisecond)
	}
	return func() {
		syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		f.Close()
	}, nil
}

func reexecRoot(a []string) error {
	self, err := os.Executable()
	if err != nil {
		self = selfPath
	}
	var c *exec.Cmd
	isTTY := isTerminal(0)
	if isTTY || lookPath("pkexec") == "" {
		if lookPath("sudo") == "" {
			return fmt.Errorf("--system needs root; run this as root")
		}
		c = exec.Command("sudo", append([]string{self}, a...)...)
	} else {
		c = exec.Command("pkexec", append([]string{self}, a...)...)
	}
	c.Stdin, c.Stdout, c.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := c.Run(); err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return exitErr{ee.ExitCode()}
		}
		return err
	}
	return nil
}

func shortPath(p string) string {
	h := homeDir()
	if h != "/" && strings.HasPrefix(p, h+"/") {
		return "~" + p[len(h):]
	}
	return p
}
