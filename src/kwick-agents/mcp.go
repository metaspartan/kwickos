package main

import (
	"bufio"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
)

var mcpVersions = []string{"2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"}

const mcpInstructions = `This is KwickOS, a small Debian-13-compatible Linux. Use these tools instead of guessing shell commands:
system_info first; permissions_get tells you what you may do. settings_list shows every setting with its allowed values;
change them with settings_set. Package changes and snapshots ask the user and an administrator. Files are limited to the
project folder and folders the user granted. To use the desktop: screenshot, then pointer_click/type_text/key_press with x,y
in the screenshot's pixels, and screenshot again to check; windows_list and window_focus manage windows. The first computer
control call asks the user once for the session; call computer_release when done. Read kwickos://docs/agents for the full
guide. If a tool says "denied" or "refused", do not retry another way: tell the user which capability is needed.`

type rpcMsg struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type rpcErr struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type Server struct {
	agent     string
	client    string
	roots     []string
	sandboxed bool
	shared    *brokerState
	outMu     sync.Mutex
	out       io.Writer
}

func newServer(agent string, roots []string, sandboxed bool) *Server {
	return &Server{agent: agent, roots: roots, sandboxed: sandboxed, shared: &brokerState{agent: agent}}
}

func (s *Server) send(v any) {
	b, err := json.Marshal(v)
	if err != nil {
		return
	}
	s.outMu.Lock()
	s.out.Write(append(b, '\n'))
	s.outMu.Unlock()
}

func (s *Server) reply(id json.RawMessage, result any) {
	s.send(map[string]any{"jsonrpc": "2.0", "id": id, "result": result})
}

func (s *Server) replyErr(id json.RawMessage, code int, msg string) {
	s.send(map[string]any{"jsonrpc": "2.0", "id": id, "error": rpcErr{code, msg}})
}

func (s *Server) serve(in io.Reader, out io.Writer) {
	s.out = out
	r := bufio.NewReaderSize(in, 1<<20)
	var wg sync.WaitGroup
	for {
		line, err := r.ReadBytes('\n')
		if len(strings.TrimSpace(string(line))) > 0 {
			trim := strings.TrimSpace(string(line))
			if strings.HasPrefix(trim, "[") {
				var batch []json.RawMessage
				if json.Unmarshal([]byte(trim), &batch) != nil {
					s.replyErr(json.RawMessage("null"), -32700, "parse error")
				}
				for _, b := range batch {
					wg.Add(1)
					go func(b json.RawMessage) { defer wg.Done(); s.handle(b) }(b)
				}
			} else {
				msg := append([]byte{}, []byte(trim)...)
				if strings.Contains(trim, `"initialize"`) {
					s.handle(msg)
				} else {
					wg.Add(1)
					go func() { defer wg.Done(); s.handle(msg) }()
				}
			}
		}
		if err != nil {
			break
		}
	}
	wg.Wait()
}

func (s *Server) handle(raw []byte) {
	var m rpcMsg
	if err := json.Unmarshal(raw, &m); err != nil {
		s.replyErr(json.RawMessage("null"), -32700, "parse error")
		return
	}
	isReq := len(m.ID) > 0 && string(m.ID) != "null"
	if m.Method == "" {
		return
	}
	switch m.Method {
	case "initialize":
		var p struct {
			ProtocolVersion string `json:"protocolVersion"`
			ClientInfo      struct {
				Name    string `json:"name"`
				Version string `json:"version"`
			} `json:"clientInfo"`
		}
		json.Unmarshal(m.Params, &p)
		s.client = p.ClientInfo.Name
		ver := "2025-06-18"
		for _, v := range mcpVersions {
			if v == p.ProtocolVersion {
				ver = v
			}
		}
		s.reply(m.ID, map[string]any{
			"protocolVersion": ver,
			"capabilities":    map[string]any{"tools": map[string]any{"listChanged": false}, "resources": map[string]any{"listChanged": false}},
			"serverInfo":      map[string]any{"name": "kwick-mcp", "title": "KwickOS", "version": version},
			"instructions":    mcpInstructions,
		})
		auditLog(auditEntry{Agent: s.agent, Client: s.client, Tool: "initialize", Decision: "allow", OK: true, Summary: "MCP session started (" + p.ClientInfo.Name + " " + p.ClientInfo.Version + ")"})
	case "ping":
		s.reply(m.ID, map[string]any{})
	case "tools/list":
		var list []map[string]any
		for _, t := range toolTable() {
			list = append(list, t.describe())
		}
		s.reply(m.ID, map[string]any{"tools": list})
	case "tools/call":
		var p struct {
			Name      string         `json:"name"`
			Arguments map[string]any `json:"arguments"`
		}
		if err := json.Unmarshal(m.Params, &p); err != nil {
			s.replyErr(m.ID, -32602, "invalid params")
			return
		}
		res, ok := s.callTool(p.Name, p.Arguments)
		if !ok {
			s.replyErr(m.ID, -32602, "unknown tool: "+p.Name)
			return
		}
		s.reply(m.ID, res)
	case "resources/list":
		s.reply(m.ID, map[string]any{"resources": []map[string]any{
			{"uri": "kwickos://docs/agents", "name": "agents", "title": "How an AI agent should operate KwickOS", "mimeType": "text/markdown"},
			{"uri": inferenceDocURI, "name": "inference", "title": "Local models: the inference endpoint on KwickOS", "mimeType": "text/markdown"},
		}})
	case "resources/templates/list":
		s.reply(m.ID, map[string]any{"resourceTemplates": []any{}})
	case "resources/read":
		var p struct {
			URI string `json:"uri"`
		}
		json.Unmarshal(m.Params, &p)
		if p.URI == inferenceDocURI {
			s.reply(m.ID, inferenceDocResource())
			return
		}
		if p.URI != "kwickos://docs/agents" {
			s.replyErr(m.ID, -32002, "resource not found")
			return
		}
		b, err := os.ReadFile(agentsDocPath)
		if err != nil {
			b, err = os.ReadFile("/usr/share/doc/kwick-agents/AGENTS.md")
		}
		if err != nil {
			b = []byte(mcpInstructions)
		}
		s.reply(m.ID, map[string]any{"contents": []map[string]any{{"uri": p.URI, "mimeType": "text/markdown", "text": string(b)}}})
	case "prompts/list":
		s.reply(m.ID, map[string]any{"prompts": []any{}})
	default:
		if isReq {
			s.replyErr(m.ID, -32601, "method not found: "+m.Method)
		}
	}
}

type toolResult struct {
	Data  any
	Text  string
	Image []byte
	Mime  string
}

func (s *Server) callTool(name string, args map[string]any) (map[string]any, bool) {
	var t *tool
	for _, x := range toolTable() {
		if x.Name == name {
			x := x
			t = &x
		}
	}
	if t == nil {
		return nil, false
	}
	if args == nil {
		args = map[string]any{}
	}
	detail := t.Name
	if t.detail != nil {
		detail = t.detail(s, args)
	}
	entry := auditEntry{Agent: s.agent, Client: s.client, Tool: t.Name, Capability: t.Cap, Summary: detail}
	fail := func(msg string) map[string]any {
		entry.Error = msg
		auditLog(entry)
		return map[string]any{"content": []map[string]any{{"type": "text", "text": msg}}, "isError": true}
	}
	if t.precheck != nil {
		if err := t.precheck(s, args); err != nil {
			entry.Decision = "rejected"
			return fail(err.Error()), true
		}
	}
	d := decide(s.agent, t.Cap)
	if t.noSession && d != "deny" {
		d = "allow"
	}
	if d != "deny" && !t.noSession && (t.Cap == ctlCap || (t.Cap == "screen.capture" && d == "ask")) && s.shared.active() != nil {
		d = "session"
	}
	switch d {
	case "session":
		entry.Decision = "session"
	case "allow":
		entry.Decision = "allow"
	case "ask":
		ask := detail
		if t.Cap == ctlCap {
			total, _ := ctlLimits()
			ask = fmt.Sprintf("Control your mouse, keyboard, windows and clipboard for up to %d minutes, until it is done or you stop it (%sthe Stop button shown at the top of the screen). Password and permission prompts stay off limits.\n\nFirst action: %s", int(total.Minutes()), hotkeyText(), detail)
		}
		ok, how := requestConsent(s.agent, s.client, t.Cap, ask)
		entry.Decision = "ask:" + how
		if !ok {
			if how == "timeout" {
				return fail(fmt.Sprintf("Not done: the user did not answer the permission request for %s. They can answer with 'kwick-agents consent' or allow it with 'kwick-agents grant %s %s allow'.", t.Cap, s.agent, t.Cap)), true
			}
			return fail(fmt.Sprintf("Denied by the user: %s needs the %s permission. Do not retry; tell the user what you wanted to do.", t.Name, t.Cap)), true
		}
	default:
		entry.Decision = "deny"
		return fail(fmt.Sprintf("Denied: your KwickOS permissions do not allow %s (%s). The user can change this in Settings > Agents or with 'kwick-agents grant %s %s allow'.", t.Name, t.Cap, s.agent, t.Cap)), true
	}
	if t.Cap == ctlCap && !t.noSession && d != "session" {
		if _, err := s.shared.startControl(s, entry.Decision); err != nil {
			return fail("Could not start computer control: " + err.Error()), true
		}
	}
	r, err := t.fn(s, args)
	if err != nil {
		entry.OK = false
		return fail(err.Error()), true
	}
	entry.OK = true
	auditLog(entry)
	var content []map[string]any
	out := map[string]any{}
	if r.Image != nil {
		content = append(content, map[string]any{"type": "image", "data": base64.StdEncoding.EncodeToString(r.Image), "mimeType": r.Mime})
	}
	text := r.Text
	if r.Data != nil {
		b, _ := json.MarshalIndent(r.Data, "", "  ")
		if text == "" {
			text = string(b)
		}
		if _, isObj := r.Data.(map[string]any); isObj {
			out["structuredContent"] = r.Data
		} else {
			out["structuredContent"] = map[string]any{"result": r.Data}
		}
	}
	if text != "" {
		content = append(content, map[string]any{"type": "text", "text": text})
	}
	out["content"] = content
	out["isError"] = false
	return out, true
}

func (s *Server) allowedRoots() []string {
	r := append([]string{}, s.roots...)
	r = append(r, loadGrants().folders(s.agent)...)
	return r
}

func within(p, root string) bool {
	root = filepath.Clean(root)
	return p == root || strings.HasPrefix(p, root+"/") || root == "/"
}

func (s *Server) resolvePath(p string, mustExist bool) (string, error) {
	if p == "" {
		return "", fmt.Errorf("path is required")
	}
	p = expandHome(p)
	if !filepath.IsAbs(p) {
		if len(s.roots) == 0 {
			return "", fmt.Errorf("use an absolute path; this session has no project folder")
		}
		p = filepath.Join(s.roots[0], p)
	}
	p = filepath.Clean(p)
	real := p
	if r, err := filepath.EvalSymlinks(p); err == nil {
		real = r
	} else if mustExist {
		return "", fmt.Errorf("%s does not exist", p)
	} else {
		dir := filepath.Dir(p)
		for !exists(dir) && dir != "/" {
			dir = filepath.Dir(dir)
		}
		if r, err := filepath.EvalSymlinks(dir); err == nil {
			rel, _ := filepath.Rel(dir, p)
			real = filepath.Join(r, rel)
		}
	}
	for _, root := range s.allowedRoots() {
		rr := root
		if r, err := filepath.EvalSymlinks(root); err == nil {
			rr = r
		}
		if within(real, rr) {
			return real, nil
		}
	}
	roots := s.allowedRoots()
	if len(roots) == 0 {
		return "", fmt.Errorf("Denied: %s has no folders it may use. The user can grant one with 'kwick-agents folders %s add PATH' or start the agent inside a project folder.", s.agent, s.agent)
	}
	return "", fmt.Errorf("Denied: %s is outside the folders %s may use (%s). The user can grant it with 'kwick-agents folders %s add PATH'.", p, s.agent, strings.Join(roots, ", "), s.agent)
}

func ancestorEnv(key string) string {
	pid := os.Getppid()
	for i := 0; i < 32 && pid > 1; i++ {
		if b, err := os.ReadFile(fmt.Sprintf("/proc/%d/environ", pid)); err == nil {
			for _, kv := range strings.Split(string(b), "\x00") {
				if strings.HasPrefix(kv, key+"=") {
					return kv[len(key)+1:]
				}
			}
		}
		st, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", pid))
		if err != nil {
			break
		}
		s := string(st)
		j := strings.LastIndexByte(s, ')')
		if j < 0 {
			break
		}
		f := strings.Fields(s[j+1:])
		if len(f) < 2 {
			break
		}
		var pp int
		fmt.Sscanf(f[1], "%d", &pp)
		pid = pp
	}
	return ""
}

func brokerSocket() (string, bool) {
	if s := os.Getenv("KWICK_MCP_SOCKET"); s != "" {
		return s, os.Getenv("KWICK_AGENT_SANDBOX") == "1" || s == "/run/kwick-mcp.sock"
	}
	if exists("/run/kwick-mcp.sock") {
		return "/run/kwick-mcp.sock", true
	}
	if s := ancestorEnv("KWICK_MCP_SOCKET"); s != "" && exists(s) {
		return s, false
	}
	return "", false
}

func mcpMain(o opts) int {
	sock, inSandbox := brokerSocket()
	if inSandbox {
		os.Setenv("KWICK_AGENT_SANDBOX", "1")
	}
	if sock != "" && o.agent == "" {
		conn, err := net.Dial("unix", sock)
		if err == nil {
			done := make(chan struct{})
			go func() {
				io.Copy(os.Stdout, conn)
				close(done)
			}()
			io.Copy(conn, os.Stdin)
			if uc, ok := conn.(*net.UnixConn); ok {
				uc.CloseWrite()
			}
			<-done
			return 0
		}
		if os.Getenv("KWICK_AGENT_SANDBOX") == "1" {
			fmt.Fprintf(os.Stderr, "kwick-mcp: cannot reach the KwickOS broker at %s: %v\n", sock, err)
			return 1
		}
	}
	agent := o.agent
	if agent == "" {
		agent = os.Getenv("KWICK_AGENT")
	}
	if agent == "" {
		agent = ancestorEnv("KWICK_AGENT")
	}
	if agent == "" {
		agent = "external"
	}
	if os.Getenv("KWICK_AGENT_SANDBOX") == "1" {
		fmt.Fprintln(os.Stderr, "kwick-mcp: inside a sandbox without a broker; refusing to serve")
		return 1
	}
	if a, err := canonicalAgent(agent); err == nil {
		agent = a
	}
	var roots []string
	if cwd, err := os.Getwd(); err == nil && o.agent != "" && projectOK(cwd) {
		roots = append(roots, cwd)
	}
	s := newServer(agent, roots, false)
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP)
	go func() {
		<-sigs
		s.shared.stopControl("the MCP server was stopped")
		os.Exit(0)
	}()
	s.serve(os.Stdin, os.Stdout)
	s.shared.stopControl("the MCP client disconnected")
	return 0
}

func cmdMCP(c *Catalog, o opts, pos []string) int {
	sub := "status"
	if len(pos) > 0 {
		sub = pos[0]
	}
	switch sub {
	case "serve":
		return mcpMain(o)
	case "tools":
		type row struct {
			Name        string `json:"name"`
			Capability  string `json:"capability"`
			Description string `json:"description"`
		}
		var rows []row
		for _, t := range toolTable() {
			rows = append(rows, row{t.Name, t.Cap, t.Description})
		}
		if o.json {
			emitJSON(map[string]any{"schema": 1, "tools": rows, "capabilities": capabilities})
		} else {
			for _, r := range rows {
				fmt.Printf("%-20s %-18s %s\n", r.Name, r.Capability, r.Description)
			}
		}
		return 0
	case "enable", "disable":
		if len(pos) != 2 {
			warnf("usage: kwick-agents mcp %s NAME", sub)
			return 2
		}
		e, err := c.get(pos[1])
		if err != nil {
			warnf("%v", err)
			return 2
		}
		var f string
		if sub == "enable" {
			f, err = mcpEnable(e)
		} else {
			f, err = mcpDisable(e)
		}
		if err != nil {
			warnf("%v", err)
			return 1
		}
		if f == "" {
			if e.MCPHint != "" {
				fmt.Println(e.MCPHint)
			} else {
				fmt.Printf("%s has no MCP client configuration that kwick-agents can edit\n", e.Name)
			}
			return 0
		}
		fmt.Printf("%sd kwick-mcp in %s\n", sub, shortPath(f))
		return 0
	case "status":
		type row struct {
			Name      string `json:"name"`
			Supported bool   `json:"supported"`
			Enabled   bool   `json:"enabled"`
			Config    string `json:"config,omitempty"`
			Hint      string `json:"hint,omitempty"`
		}
		var rows []row
		names := []string{}
		for _, e := range c.Entries {
			if e.Kind == "runtime" || e.Hidden {
				continue
			}
			if _, _, ok := findInstalled(e.Name); !ok && !o.installed {
				continue
			}
			names = append(names, e.Name)
		}
		sort.Strings(names)
		for _, n := range names {
			e := c.byName[n]
			rows = append(rows, row{Name: n, Supported: e.MCP != "" && e.MCP != "none", Enabled: mcpConfigured(e), Config: mcpConfigFile(e), Hint: e.MCPHint})
		}
		if rows == nil {
			rows = []row{}
		}
		if o.json {
			emitJSON(map[string]any{"schema": 1, "server": mcpPath, "agents": rows})
		} else {
			if len(rows) == 0 {
				fmt.Println("no agents installed")
			}
			for _, r := range rows {
				st := "not supported"
				if r.Supported {
					st = "not registered"
					if r.Enabled {
						st = "registered in " + shortPath(r.Config)
					}
				}
				fmt.Printf("%-12s %s\n", r.Name, st)
			}
		}
		return 0
	}
	warnf("usage: kwick-agents mcp serve|enable NAME|disable NAME|status|tools")
	return 2
}
