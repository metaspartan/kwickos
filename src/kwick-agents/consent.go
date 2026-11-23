package main

import (
	"bufio"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

type capInfo struct {
	Name        string `json:"name"`
	Default     string `json:"default"`
	Description string `json:"description"`
	Privileged  bool   `json:"privileged"`
}

var capabilities = []capInfo{
	{"system.read", "allow", "Read system information, installed packages, available updates, snapshots, settings and the list of apps", false},
	{"files.read", "allow", "List and read files in the project folder and in folders you granted", false},
	{"files.write", "ask", "Create and change files in the project folder and in folders you granted", false},
	{"notify", "allow", "Show desktop notifications", false},
	{"settings.write", "ask", "Change settings: layout, appearance, dock, effects, fonts, display, sound, Wi-Fi, Bluetooth, power and updates (system-wide ones also ask for an administrator password)", false},
	{"apps.launch", "ask", "Open applications", false},
	{"screen.capture", "ask", "Take a screenshot of your screen", false},
	{"computer.control", "ask", "Use the computer: move the pointer, click, type, manage windows and the clipboard (one approval lasts for the agent's session)", false},
	{"packages.manage", "ask", "Install packages and system updates; also asks for an administrator password", true},
	{"snapshots.manage", "ask", "Create system snapshots; also asks for an administrator password", true},
}

func capByName(n string) (capInfo, bool) {
	for _, c := range capabilities {
		if c.Name == n {
			return c, true
		}
	}
	return capInfo{}, false
}

type AgentGrants struct {
	Caps    map[string]string `json:"caps,omitempty"`
	Folders []string          `json:"folders,omitempty"`
}

type Grants struct {
	Schema int                     `json:"schema"`
	Agents map[string]*AgentGrants `json:"agents"`
}

func grantsPath(sc Scope) string { return filepath.Join(sc.Config, "grants.json") }

var grantsMu sync.Mutex

func loadGrantsFrom(sc Scope) *Grants {
	g := &Grants{Schema: 1, Agents: map[string]*AgentGrants{}}
	readJSONFile(grantsPath(sc), g)
	if g.Agents == nil {
		g.Agents = map[string]*AgentGrants{}
	}
	return g
}

func loadGrants() *Grants { return loadGrantsFrom(userScope()) }

func saveGrants(g *Grants) error {
	os.MkdirAll(userScope().Config, 0o700)
	return writeJSONFile(grantsPath(userScope()), g, 0o600)
}

func (g *Grants) agent(n string) *AgentGrants {
	a := g.Agents[n]
	if a == nil {
		a = &AgentGrants{Caps: map[string]string{}}
		g.Agents[n] = a
	}
	if a.Caps == nil {
		a.Caps = map[string]string{}
	}
	return a
}

func (g *Grants) folders(n string) []string {
	if a := g.Agents[n]; a != nil {
		return a.Folders
	}
	return nil
}

func policyDecision(agent, cap string) string {
	sys := loadGrantsFrom(systemScope())
	for _, n := range []string{agent, "*"} {
		if a := sys.Agents[n]; a != nil && a.Caps[cap] == "deny" {
			return "deny"
		}
	}
	return ""
}

func decide(agent, cap string) string {
	if d := policyDecision(agent, cap); d != "" {
		return d
	}
	g := loadGrants()
	if a := g.Agents[agent]; a != nil {
		if v := a.Caps[cap]; v != "" {
			return v
		}
	}
	sys := loadGrantsFrom(systemScope())
	for _, n := range []string{agent, "*"} {
		if a := sys.Agents[n]; a != nil && a.Caps[cap] != "" {
			return a.Caps[cap]
		}
	}
	if c, ok := capByName(cap); ok {
		return c.Default
	}
	return "deny"
}

func effectiveGrants(g *Grants, agent string) map[string]string {
	out := map[string]string{}
	for _, c := range capabilities {
		out[c.Name] = decide(agent, c.Name)
	}
	return out
}

func setGrant(agent, cap, v string) error {
	grantsMu.Lock()
	defer grantsMu.Unlock()
	g := loadGrants()
	a := g.agent(agent)
	if v == "default" {
		delete(a.Caps, cap)
	} else {
		a.Caps[cap] = v
	}
	return saveGrants(g)
}

func guiEnv() bool {
	return os.Getenv("WAYLAND_DISPLAY") != "" || os.Getenv("DISPLAY") != ""
}

func askDialog(title, text string) (string, bool) {
	if !guiEnv() {
		return "", false
	}
	de := strings.ToLower(os.Getenv("XDG_CURRENT_DESKTOP"))
	tools := []string{"zenity", "kdialog"}
	if strings.Contains(de, "kde") {
		tools = []string{"kdialog", "zenity"}
	}
	for _, t := range tools {
		if lookPath(t) == "" {
			continue
		}
		var c *exec.Cmd
		if t == "kdialog" {
			c = exec.Command("kdialog", "--title", title, "--yesnocancel", text, "--yes-label", "Allow once", "--no-label", "Always allow", "--cancel-label", "Deny")
		} else {
			c = exec.Command("zenity", "--question", "--title="+title, "--text="+text, "--ok-label=Allow once", "--cancel-label=Deny", "--extra-button=Always allow", "--width=460", "--icon=dialog-password")
		}
		out, err := c.Output()
		code := exitCode(err)
		if err != nil && code == 127 {
			continue
		}
		if t == "kdialog" {
			switch code {
			case 0:
				return "once", true
			case 1:
				return "always", true
			case 2:
				return "deny", true
			}
			continue
		}
		if strings.TrimSpace(string(out)) == "Always allow" {
			return "always", true
		}
		if code == 0 {
			return "once", true
		}
		if code == 1 || code == 5 {
			return "deny", true
		}
	}
	if lookPath("notify-send") != "" {
		c := exec.Command("notify-send", "--app-name=KwickOS Agents", "--urgency=critical", "--icon=dialog-password", "--wait",
			"--action=once=Allow once", "--action=always=Always allow", "--action=deny=Deny", title, text)
		out, err := c.Output()
		if err == nil {
			switch strings.TrimSpace(string(out)) {
			case "once":
				return "once", true
			case "always":
				return "always", true
			default:
				return "deny", true
			}
		}
	}
	return "", false
}

type pendingReq struct {
	ID         string `json:"id"`
	Agent      string `json:"agent"`
	Client     string `json:"client,omitempty"`
	Capability string `json:"capability"`
	Detail     string `json:"detail"`
	Time       string `json:"time"`
	Expires    string `json:"expires"`
}

func pendingDir() string { return filepath.Join(runtimeDir(), "pending") }

func askPending(agent, client, cap, detail string, wait time.Duration) string {
	d := pendingDir()
	os.MkdirAll(d, 0o700)
	b := make([]byte, 4)
	rand.Read(b)
	id := hex.EncodeToString(b)
	req := pendingReq{ID: id, Agent: agent, Client: client, Capability: cap, Detail: detail, Time: nowStamp(), Expires: time.Now().Add(wait).UTC().Format(time.RFC3339)}
	f := filepath.Join(d, id+".json")
	ans := filepath.Join(d, id+".answer")
	if writeJSONFile(f, req, 0o600) != nil {
		return "deny"
	}
	defer os.Remove(f)
	defer os.Remove(ans)
	deadline := time.Now().Add(wait)
	for time.Now().Before(deadline) {
		if b, err := os.ReadFile(ans); err == nil {
			switch strings.TrimSpace(string(b)) {
			case "once", "always":
				return strings.TrimSpace(string(b))
			}
			return "deny"
		}
		time.Sleep(300 * time.Millisecond)
	}
	return "timeout"
}

var consentMu sync.Mutex

func requestConsent(agent, client, cap, detail string) (bool, string) {
	consentMu.Lock()
	defer consentMu.Unlock()
	if d := decide(agent, cap); d == "allow" {
		return true, "always"
	} else if d == "deny" {
		return false, "denied"
	}
	c, _ := capByName(cap)
	who := agent
	if cat, err := loadCatalog(); err == nil {
		if e, ok := cat.byName[agent]; ok && e.Title != "" {
			who = e.Title
		}
	}
	if client != "" && client != agent && !strings.EqualFold(client, who) {
		who = who + " (" + client + ")"
	}
	text := fmt.Sprintf("The AI agent %s asks to: %s.\n\n%s\n\nCapability: %s", who, strings.ToLower(c.Description[:1])+c.Description[1:], detail, cap)
	ans, ok := askNative(consentTitle, who, cap, c.Description, detail)
	if !ok {
		ans, ok = askDialog(consentTitle, text)
	}
	if !ok {
		wait := 90 * time.Second
		if os.Getenv("KWICK_AGENTS_CONSENT_WAIT") != "" {
			if d, err := time.ParseDuration(os.Getenv("KWICK_AGENTS_CONSENT_WAIT")); err == nil {
				wait = d
			}
		}
		ans = askPending(agent, client, cap, detail, wait)
		if ans == "timeout" {
			return false, "timeout"
		}
	}
	switch ans {
	case "always":
		setGrant(agent, cap, "allow")
		return true, "always"
	case "once":
		return true, "once"
	}
	return false, "denied"
}

func cmdConsent(o opts, pos []string) error {
	sub := "list"
	if len(pos) > 0 {
		sub = pos[0]
	}
	d := pendingDir()
	switch sub {
	case "list", "ls":
		ms, _ := filepath.Glob(filepath.Join(d, "*.json"))
		reqs := []pendingReq{}
		for _, m := range ms {
			var r pendingReq
			if readJSONFile(m, &r) == nil {
				reqs = append(reqs, r)
			}
		}
		sort.Slice(reqs, func(i, j int) bool { return reqs[i].Time < reqs[j].Time })
		if o.json {
			emitJSON(map[string]any{"schema": 1, "pending": reqs})
			return nil
		}
		if len(reqs) == 0 {
			fmt.Println("no pending requests")
		}
		for _, r := range reqs {
			fmt.Printf("%s  %-12s %-16s %s\n", r.ID, r.Agent, r.Capability, r.Detail)
		}
		if len(reqs) > 0 {
			fmt.Println("answer with: kwick-agents consent allow|always|deny ID")
		}
		return nil
	case "allow", "once", "always", "deny":
		if len(pos) != 2 || !regexpHex8(pos[1]) {
			return fmt.Errorf("usage: kwick-agents consent %s ID", sub)
		}
		if !exists(filepath.Join(d, pos[1]+".json")) {
			return fmt.Errorf("no pending request %s", pos[1])
		}
		v := sub
		if v == "allow" {
			v = "once"
		}
		return os.WriteFile(filepath.Join(d, pos[1]+".answer"), []byte(v+"\n"), 0o600)
	}
	return fmt.Errorf("usage: kwick-agents consent [list|allow ID|always ID|deny ID]")
}

func regexpHex8(s string) bool {
	if len(s) != 8 {
		return false
	}
	_, err := hex.DecodeString(s)
	return err == nil
}

func cmdGrants(c *Catalog, o opts, pos []string) error {
	g := loadGrants()
	names := map[string]bool{}
	if len(pos) > 0 {
		e, err := c.get(pos[0])
		if err != nil {
			return err
		}
		names[e.Name] = true
	} else {
		for n := range g.Agents {
			names[n] = true
		}
		for _, sc := range []Scope{userScope(), systemScope()} {
			for n := range loadState(sc).Agents {
				if e := c.byName[n]; e != nil && e.Kind != "runtime" {
					names[n] = true
				}
			}
		}
	}
	sorted := []string{}
	for n := range names {
		sorted = append(sorted, n)
	}
	sort.Strings(sorted)
	type ag struct {
		Caps    map[string]string `json:"caps"`
		Folders []string          `json:"folders"`
	}
	out := map[string]ag{}
	for _, n := range sorted {
		f := g.folders(n)
		if f == nil {
			f = []string{}
		}
		out[n] = ag{Caps: effectiveGrants(g, n), Folders: f}
	}
	if o.json {
		emitJSON(map[string]any{"schema": 1, "capabilities": capabilities, "agents": out})
		return nil
	}
	if len(sorted) == 0 {
		fmt.Println("no agents installed; defaults:")
		for _, cp := range capabilities {
			fmt.Printf("  %-18s %-6s %s\n", cp.Name, cp.Default, cp.Description)
		}
		return nil
	}
	for _, n := range sorted {
		fmt.Println(n)
		for _, cp := range capabilities {
			fmt.Printf("  %-18s %s\n", cp.Name, out[n].Caps[cp.Name])
		}
		if len(out[n].Folders) > 0 {
			fmt.Printf("  folders            %s\n", strings.Join(out[n].Folders, " "))
		}
	}
	return nil
}

func cmdGrant(o opts, pos []string) error {
	if len(pos) != 3 {
		return fmt.Errorf("usage: kwick-agents grant NAME CAPABILITY allow|ask|deny|default")
	}
	agent, err := canonicalAgent(pos[0])
	if err != nil {
		return err
	}
	if _, ok := capByName(pos[1]); !ok {
		var n []string
		for _, c := range capabilities {
			n = append(n, c.Name)
		}
		return fmt.Errorf("unknown capability %q (one of: %s)", pos[1], strings.Join(n, ", "))
	}
	switch pos[2] {
	case "allow", "ask", "deny", "default":
	default:
		return fmt.Errorf("value must be allow, ask, deny or default")
	}
	if err := setGrant(agent, pos[1], pos[2]); err != nil {
		return err
	}
	auditLog(auditEntry{Agent: agent, Tool: "cli", Capability: pos[1], Decision: pos[2], OK: true, Summary: "grant set by the user"})
	return nil
}

func cmdFolders(o opts, pos []string) error {
	if len(pos) < 1 {
		return fmt.Errorf("usage: kwick-agents folders NAME [add|rm PATH]")
	}
	agent, err := canonicalAgent(pos[0])
	if err != nil {
		return err
	}
	grantsMu.Lock()
	defer grantsMu.Unlock()
	g := loadGrants()
	if len(pos) == 1 {
		f := g.folders(agent)
		if f == nil {
			f = []string{}
		}
		if o.json {
			emitJSON(map[string]any{"agent": agent, "folders": f})
		} else {
			for _, p := range f {
				fmt.Println(p)
			}
		}
		return nil
	}
	if len(pos) != 3 {
		return fmt.Errorf("usage: kwick-agents folders NAME [add|rm PATH]")
	}
	p, err := filepath.Abs(expandHome(pos[2]))
	if err != nil {
		return err
	}
	if r, err := filepath.EvalSymlinks(p); err == nil {
		p = r
	}
	a := g.agent(agent)
	switch pos[1] {
	case "add":
		st, err := os.Stat(p)
		if err != nil || !st.IsDir() {
			return fmt.Errorf("%s is not a folder", p)
		}
		if p == "/" || p == homeDir() {
			say("Warning: %s gives %s file access to everything below it.", p, agent)
		}
		for _, f := range a.Folders {
			if f == p {
				return nil
			}
		}
		a.Folders = append(a.Folders, p)
	case "rm", "remove":
		var keep []string
		for _, f := range a.Folders {
			if f != p {
				keep = append(keep, f)
			}
		}
		a.Folders = keep
	default:
		return fmt.Errorf("usage: kwick-agents folders NAME [add|rm PATH]")
	}
	if err := saveGrants(g); err != nil {
		return err
	}
	auditLog(auditEntry{Agent: agent, Tool: "cli", Capability: "folders", Decision: pos[1], OK: true, Summary: p})
	return nil
}

type auditEntry struct {
	Time       string `json:"time"`
	Agent      string `json:"agent"`
	Client     string `json:"client,omitempty"`
	Tool       string `json:"tool"`
	Capability string `json:"capability,omitempty"`
	Decision   string `json:"decision"`
	OK         bool   `json:"ok"`
	Summary    string `json:"summary,omitempty"`
	Error      string `json:"error,omitempty"`
}

var auditMu sync.Mutex

func auditPath() string { return filepath.Join(userScope().State, "audit.jsonl") }

func auditLog(a auditEntry) {
	auditMu.Lock()
	defer auditMu.Unlock()
	if a.Time == "" {
		a.Time = nowStamp()
	}
	if len(a.Summary) > 400 {
		a.Summary = a.Summary[:400] + "..."
	}
	p := auditPath()
	os.MkdirAll(filepath.Dir(p), 0o700)
	if st, err := os.Stat(p); err == nil && st.Size() > 5<<20 {
		os.Rename(p, p+".1")
	}
	f, err := os.OpenFile(p, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return
	}
	defer f.Close()
	b, _ := json.Marshal(a)
	f.Write(append(b, '\n'))
}

func readAudit(agent string, n int) []auditEntry {
	var all []auditEntry
	for _, p := range []string{auditPath() + ".1", auditPath()} {
		f, err := os.Open(p)
		if err != nil {
			continue
		}
		sc := bufio.NewScanner(f)
		sc.Buffer(make([]byte, 64<<10), 1<<20)
		for sc.Scan() {
			var a auditEntry
			if json.Unmarshal(sc.Bytes(), &a) == nil && (agent == "" || a.Agent == agent) {
				all = append(all, a)
			}
		}
		f.Close()
	}
	if n > 0 && len(all) > n {
		all = all[len(all)-n:]
	}
	if all == nil {
		all = []auditEntry{}
	}
	return all
}

func cmdAudit(o opts) error {
	agent := o.agent
	if agent != "" {
		a, err := canonicalAgent(agent)
		if err != nil {
			return err
		}
		agent = a
	}
	es := readAudit(agent, o.n)
	if o.json {
		emitJSON(map[string]any{"schema": 1, "path": auditPath(), "entries": es})
		return nil
	}
	for _, a := range es {
		ok := "ok"
		if !a.OK {
			ok = "FAILED"
		}
		fmt.Printf("%s  %-12s %-18s %-16s %-8s %-6s %s\n", a.Time, a.Agent, a.Tool, a.Capability, a.Decision, ok, a.Summary)
	}
	return nil
}
