package main

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
)

var (
	varRe  = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]{0,127}$`)
	nameRe = regexp.MustCompile(`^[a-z0-9][a-z0-9._-]{0,63}$`)
)

func keyIndexPath() string { return filepath.Join(userScope().Config, "keys.json") }
func keyFilePath() string  { return filepath.Join(userScope().Config, "secrets.json") }

func loadKeyIndex() map[string]map[string]string {
	idx := map[string]map[string]string{}
	readJSONFile(keyIndexPath(), &idx)
	return idx
}

func saveKeyIndex(idx map[string]map[string]string) error {
	os.MkdirAll(userScope().Config, 0o700)
	return writeJSONFile(keyIndexPath(), idx, 0o600)
}

var (
	ssOnce sync.Once
	ssOK   bool
)

func sessionBusEnv() []string {
	env := os.Environ()
	if os.Getenv("DBUS_SESSION_BUS_ADDRESS") == "" {
		if rd := os.Getenv("XDG_RUNTIME_DIR"); rd != "" && exists(filepath.Join(rd, "bus")) {
			env = append(env, "DBUS_SESSION_BUS_ADDRESS=unix:path="+filepath.Join(rd, "bus"))
		}
	}
	return env
}

func secretServiceAvailable() bool {
	ssOnce.Do(func() {
		switch os.Getenv("KWICK_AGENTS_KEYSTORE") {
		case "file":
			return
		}
		if lookPath("secret-tool") == "" {
			return
		}
		env := sessionBusEnv()
		hasBus := false
		for _, kv := range env {
			if strings.HasPrefix(kv, "DBUS_SESSION_BUS_ADDRESS=") && len(kv) > 25 {
				hasBus = true
			}
		}
		if !hasBus {
			return
		}
		c := exec.Command("secret-tool", "search", "service", "kwick-agents-probe")
		c.Env = env
		var stderr bytes.Buffer
		c.Stderr = &stderr
		c.Run()
		ssOK = strings.TrimSpace(stderr.String()) == ""
	})
	return ssOK
}

func backendName() string {
	if secretServiceAvailable() {
		return "secret-service"
	}
	return "file"
}

func fileSecrets() map[string]map[string]string {
	m := map[string]map[string]string{}
	readJSONFile(keyFilePath(), &m)
	return m
}

func saveFileSecrets(m map[string]map[string]string) error {
	d := userScope().Config
	os.MkdirAll(d, 0o700)
	os.Chmod(d, 0o700)
	return writeJSONFile(keyFilePath(), m, 0o600)
}

func secretSet(agent, v, val string) (string, error) {
	backend := backendName()
	if backend == "secret-service" {
		c := exec.Command("secret-tool", "store", "--label=kwick-agents: "+agent+" "+v, "service", "kwick-agents", "agent", agent, "var", v)
		c.Env = sessionBusEnv()
		c.Stdin = strings.NewReader(val)
		var stderr bytes.Buffer
		c.Stderr = &stderr
		if err := c.Run(); err != nil {
			return "", fmt.Errorf("secret service: %v %s", err, strings.TrimSpace(stderr.String()))
		}
	} else {
		m := fileSecrets()
		if m[agent] == nil {
			m[agent] = map[string]string{}
		}
		m[agent][v] = val
		if err := saveFileSecrets(m); err != nil {
			return "", err
		}
	}
	idx := loadKeyIndex()
	if idx[agent] == nil {
		idx[agent] = map[string]string{}
	}
	idx[agent][v] = backend
	return backend, saveKeyIndex(idx)
}

func secretGet(agent, v, backend string) (string, bool) {
	if backend == "secret-service" {
		if !secretServiceAvailable() {
			return "", false
		}
		c := exec.Command("secret-tool", "lookup", "service", "kwick-agents", "agent", agent, "var", v)
		c.Env = sessionBusEnv()
		out, err := c.Output()
		if err != nil {
			return "", false
		}
		return strings.TrimRight(string(out), "\n"), true
	}
	m := fileSecrets()
	val, ok := m[agent][v]
	return val, ok
}

func secretRm(agent, v string) error {
	idx := loadKeyIndex()
	backend := idx[agent][v]
	if backend == "" {
		return fmt.Errorf("no key %s stored for %s", v, agent)
	}
	if backend == "secret-service" {
		c := exec.Command("secret-tool", "clear", "service", "kwick-agents", "agent", agent, "var", v)
		c.Env = sessionBusEnv()
		c.Run()
	} else {
		m := fileSecrets()
		delete(m[agent], v)
		if len(m[agent]) == 0 {
			delete(m, agent)
		}
		if err := saveFileSecrets(m); err != nil {
			return err
		}
	}
	delete(idx[agent], v)
	if len(idx[agent]) == 0 {
		delete(idx, agent)
	}
	return saveKeyIndex(idx)
}

func loadSecretsFor(agent string) map[string]string {
	out := map[string]string{}
	idx := loadKeyIndex()
	for _, a := range []string{"shared", agent} {
		for v, backend := range idx[a] {
			if val, ok := secretGet(a, v, backend); ok {
				out[v] = val
			} else {
				warnf("key %s for %s could not be read from %s", v, a, backend)
			}
		}
	}
	return out
}

func keyNames(agent string) []string {
	idx := loadKeyIndex()
	set := map[string]bool{}
	for _, a := range []string{"shared", agent} {
		for v := range idx[a] {
			set[v] = true
		}
	}
	out := []string{}
	for v := range set {
		out = append(out, v)
	}
	sort.Strings(out)
	return out
}

func cmdKey(o opts, pos []string) error {
	if len(pos) == 0 {
		pos = []string{"list"}
	}
	sub := pos[0]
	switch sub {
	case "list", "ls":
		idx := loadKeyIndex()
		type row struct {
			Agent   string `json:"agent"`
			Var     string `json:"var"`
			Backend string `json:"backend"`
		}
		rows := []row{}
		for a, vs := range idx {
			if len(pos) > 1 && a != pos[1] {
				continue
			}
			for v, b := range vs {
				rows = append(rows, row{a, v, b})
			}
		}
		sort.Slice(rows, func(i, j int) bool {
			if rows[i].Agent != rows[j].Agent {
				return rows[i].Agent < rows[j].Agent
			}
			return rows[i].Var < rows[j].Var
		})
		if o.json {
			emitJSON(map[string]any{"schema": 1, "backend": backendName(), "keys": rows})
			return nil
		}
		if len(rows) == 0 {
			fmt.Printf("no keys stored (keystore: %s)\n", backendName())
		}
		for _, r := range rows {
			fmt.Printf("%-14s %-28s %s\n", r.Agent, r.Var, r.Backend)
		}
		return nil
	case "set", "add":
		if len(pos) != 3 {
			return fmt.Errorf("usage: kwick-agents key set NAME VAR   (value from stdin; NAME may be 'shared')")
		}
		agent, err := canonicalAgent(pos[1])
		if err != nil {
			return err
		}
		v := pos[2]
		if !varRe.MatchString(v) {
			return fmt.Errorf("%q is not a valid environment variable name", v)
		}
		var val string
		if o.dialog {
			who := "every agent"
			if agent != "shared" {
				who = agent
				if c, err := loadCatalog(); err == nil && c.byName[agent] != nil {
					who = c.byName[agent].Title
				}
			}
			s, err := passwordDialog(fmt.Sprintf("Enter the value of %s for %s. It is stored in your keystore and given to the agent when it starts.", v, who))
			if err != nil {
				return err
			}
			val = s
		} else if isTerminal(0) {
			s, err := readNoEcho(fmt.Sprintf("Value for %s (%s, not shown): ", v, agent))
			if err != nil {
				return err
			}
			val = s
		} else {
			r := bufio.NewReader(os.Stdin)
			s, _ := r.ReadString('\n')
			val = strings.TrimRight(s, "\r\n")
		}
		if val == "" {
			return fmt.Errorf("empty value; nothing stored")
		}
		backend, err := secretSet(agent, v, val)
		if err != nil {
			return err
		}
		auditLog(auditEntry{Agent: agent, Tool: "cli", Capability: "keys", Decision: "set", OK: true, Summary: "stored " + v + " in " + backend})
		if o.json {
			emitJSON(map[string]any{"agent": agent, "var": v, "backend": backend})
		} else {
			say("%s stored for %s (%s)", v, agent, backend)
		}
		return nil
	case "rm", "remove", "delete":
		if len(pos) != 3 {
			return fmt.Errorf("usage: kwick-agents key rm NAME VAR")
		}
		agent, err := canonicalAgent(pos[1])
		if err != nil {
			return err
		}
		if err := secretRm(agent, pos[2]); err != nil {
			return err
		}
		auditLog(auditEntry{Agent: agent, Tool: "cli", Capability: "keys", Decision: "rm", OK: true, Summary: "removed " + pos[2]})
		return nil
	}
	return fmt.Errorf("usage: kwick-agents key set|rm|list ...")
}

func passwordDialog(text string) (string, error) {
	if !guiEnv() {
		return "", fmt.Errorf("--dialog needs a desktop session")
	}
	var c *exec.Cmd
	switch {
	case lookPath("kdialog") != "" && strings.Contains(strings.ToLower(os.Getenv("XDG_CURRENT_DESKTOP")), "kde"):
		c = exec.Command("kdialog", "--title", "KwickOS Agents: API key", "--password", text)
	case lookPath("zenity") != "":
		c = exec.Command("zenity", "--password", "--title=KwickOS Agents: API key")
	case lookPath("kdialog") != "":
		c = exec.Command("kdialog", "--title", "KwickOS Agents: API key", "--password", text)
	default:
		return "", fmt.Errorf("no dialog tool (kdialog or zenity)")
	}
	out, err := c.Output()
	if err != nil {
		return "", fmt.Errorf("cancelled")
	}
	return strings.TrimRight(string(out), "\r\n"), nil
}

func canonicalAgent(a string) (string, error) {
	if a == "shared" || a == "external" {
		return a, nil
	}
	if !nameRe.MatchString(a) {
		return "", fmt.Errorf("invalid agent name %q", a)
	}
	if c, err := loadCatalog(); err == nil {
		e, err := c.get(a)
		if err != nil {
			return "", err
		}
		return e.Name, nil
	}
	return a, nil
}
