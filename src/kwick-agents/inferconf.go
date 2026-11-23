package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	localMarker   = "kwickos-local"
	localModelRef = localMarker + "/" + inferAlias
	cybaraName    = "KwickOS local (kwickos-local)"
)

var connectOrder = []string{"cybara", "opencode", "codex", "goose", "hermes", "openclaw", "omp", "aider", "claude-code"}

var connectMethod = map[string]string{
	"cybara": "api", "opencode": "config", "codex": "config", "goose": "config", "hermes": "config",
	"openclaw": "config", "omp": "config", "aider": "run --local", "claude-code": "run --local",
}

func connectFile(agent string) string {
	h := homeDir()
	cfgHome := xdg("XDG_CONFIG_HOME", ".config")
	switch agent {
	case "opencode":
		return filepath.Join(cfgHome, "opencode", "opencode.json")
	case "codex":
		return filepath.Join(h, ".codex", "config.toml")
	case "goose":
		return filepath.Join(cfgHome, "goose", "custom_providers", localMarker+".json")
	case "hermes":
		return filepath.Join(h, ".hermes", "config.yaml")
	case "openclaw":
		return filepath.Join(h, ".openclaw", "openclaw.json")
	case "omp":
		return filepath.Join(h, ".omp", "agent", "models.yml")
	case "cybara":
		return cybaraBase() + "/api/providers"
	}
	return ""
}

func agentConnections(c *Catalog, cfg *inferConfig) []agentConn {
	out := []agentConn{}
	for _, n := range connectOrder {
		a := agentConn{Name: n, Title: n, Method: connectMethod[n], Supported: true}
		if c != nil {
			if e, ok := c.byName[n]; ok {
				a.Title = e.Title
			}
		}
		_, _, a.Installed = findInstalled(n)
		switch n {
		case "aider":
			a.Note = "kwick-agents run --local aider"
			a.Connected = false
		case "claude-code":
			a.Note = "opt-in only: kwick-agents run --local claude-code (Anthropic does not support non-Claude models)"
		case "cybara":
			_, a.Connected = cfg.Connected[n]
			a.File = connectFile(n)
			a.Note = "registered through Cybara's gateway API as the provider \"" + cybaraName + "\""
		default:
			a.File = connectFile(n)
			a.Connected = connectedNow(n)
		}
		out = append(out, a)
	}
	return out
}

func connectedNow(agent string) bool {
	f := connectFile(agent)
	b, err := os.ReadFile(f)
	if err != nil {
		return false
	}
	s := string(b)
	switch agent {
	case "codex":
		return strings.Contains(s, "[model_providers."+localMarker+"]")
	case "goose":
		return true
	case "hermes":
		return strings.Contains(s, "# "+localMarker)
	case "omp":
		return yamlHasChild(s, "providers", localMarker)
	}
	var m map[string]any
	if json.Unmarshal(b, &m) != nil {
		return false
	}
	switch agent {
	case "opencode":
		_, ok := jsonGet(m, []string{"provider", localMarker})
		return ok
	case "openclaw":
		_, ok := jsonGet(m, []string{"models", "providers", localMarker})
		return ok
	}
	return false
}

func cmdInferConnect(o iopts, pos []string, on bool) error {
	c, _ := loadCatalog()
	cfg := loadInferConfig()
	names := pos
	if o.all || len(names) == 0 {
		names = nil
		for _, n := range connectOrder {
			if connectMethod[n] == "run --local" {
				continue
			}
			if _, _, ok := findInstalled(n); ok || (!on && cfg.Connected[n] != nil) {
				names = append(names, n)
			}
		}
		if len(names) == 0 {
			say("no agent that can be connected is installed (%s)", strings.Join(connectOrder[:7], ", "))
			return nil
		}
	}
	if on {
		writeEndpoint(cfg)
	}
	failed := false
	var rows []map[string]any
	for _, n := range names {
		if c != nil {
			if e, err := c.get(n); err == nil {
				n = e.Name
			}
		}
		err := connectAgent(cfg, n, on)
		row := map[string]any{"name": n, "ok": err == nil, "file": connectFile(n)}
		if err != nil {
			row["error"] = err.Error()
			failed = true
			warnf("%s: %v", n, err)
		} else if !o.json {
			verb := "connected to"
			if !on {
				verb = "disconnected from"
			}
			say("%s %s the local endpoint (%s)", n, verb, connectHint(n, on))
		}
		rows = append(rows, row)
	}
	if err := saveInferConfig(cfg); err != nil {
		return err
	}
	if o.json {
		emitJSON(map[string]any{"schema": 1, "agents": rows})
	}
	if failed {
		return exitErr{1}
	}
	return nil
}

func connectHint(n string, on bool) string {
	if !on {
		return "restored"
	}
	switch n {
	case "codex":
		return "start it with: codex --profile " + localMarker
	case "cybara":
		return "provider \"" + cybaraName + "\" is now Cybara's default"
	}
	return "model " + localModelRef + " is the default in " + shortPath(connectFile(n))
}

func connectAgent(cfg *inferConfig, n string, on bool) error {
	rec := cfg.Connected[n]
	if rec == nil {
		rec = &connRecord{Previous: map[string]any{}}
	}
	if rec.Previous == nil {
		rec.Previous = map[string]any{}
	}
	var err error
	switch n {
	case "opencode":
		err = wireOpencode(cfg, rec, on)
	case "codex":
		err = wireCodex(cfg, on)
	case "goose":
		err = wireGoose(cfg, rec, on)
	case "hermes":
		err = wireHermes(cfg, rec, on)
	case "openclaw":
		err = wireOpenclaw(cfg, rec, on)
	case "omp":
		err = wireOmp(cfg, rec, on)
	case "cybara":
		err = wireCybara(cfg, rec, on)
	case "aider":
		return fmt.Errorf("Aider has no provider file to edit; start it with: kwick-agents run --local aider")
	case "claude-code":
		return fmt.Errorf("Claude Code is never rewired permanently; for one run use: kwick-agents run --local claude-code (Anthropic does not support non-Claude models)")
	default:
		return fmt.Errorf("%s cannot be connected to the local endpoint", n)
	}
	if err != nil {
		return err
	}
	if on {
		rec.File = connectFile(n)
		rec.At = nowStamp()
		cfg.Connected[n] = rec
	} else {
		delete(cfg.Connected, n)
	}
	auditLog(auditEntry{Agent: n, Tool: "cli", Capability: "inference.manage", Decision: map[bool]string{true: "connect", false: "disconnect"}[on], OK: true, Summary: "local endpoint " + map[bool]string{true: "connected", false: "disconnected"}[on]})
	return nil
}

func ensureMap(m map[string]any, k string) (map[string]any, error) {
	v, ok := m[k]
	if !ok || v == nil {
		mm := map[string]any{}
		m[k] = mm
		return mm, nil
	}
	mm, ok := v.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("%q is not an object; edit it by hand", k)
	}
	return mm, nil
}

func modelTitle(cfg *inferConfig) string {
	if cfg.Model != "" {
		return "Local model (" + cfg.Model + ")"
	}
	return "Local model"
}

func wireOpencode(cfg *inferConfig, rec *connRecord, on bool) error {
	f := connectFile("opencode")
	m, _, err := readJSONMap(f)
	if err != nil {
		return err
	}
	if m == nil {
		if !on {
			return nil
		}
		m = map[string]any{"$schema": "https://opencode.ai/config.json"}
	}
	if on {
		prov, err := ensureMap(m, "provider")
		if err != nil {
			return err
		}
		prov[localMarker] = map[string]any{
			"npm":  "@ai-sdk/openai-compatible",
			"name": "KwickOS local (llama.cpp)",
			"options": map[string]any{
				"baseURL": cfg.baseURL() + "/v1",
				"apiKey":  "{env:" + inferKeyEnv + "}",
			},
			"models": map[string]any{inferAlias: map[string]any{"name": modelTitle(cfg), "limit": map[string]any{"context": cfg.ctx(), "output": 8192}}},
		}
		if cur, ok := m["model"]; ok && cur != localModelRef {
			rec.Previous["model"] = cur
		}
		m["model"] = localModelRef
	} else {
		if prov, ok := m["provider"].(map[string]any); ok {
			delete(prov, localMarker)
			if len(prov) == 0 {
				delete(m, "provider")
			}
		}
		if m["model"] == localModelRef {
			if p, ok := rec.Previous["model"]; ok {
				m["model"] = p
			} else {
				delete(m, "model")
			}
		}
	}
	return writeJSONKeepMode(f, m)
}

func codexBlock(cfg *inferConfig) string {
	return "[model_providers." + localMarker + "]\n" +
		"name = \"KwickOS local (llama.cpp)\"\n" +
		"base_url = \"" + cfg.baseURL() + "/v1\"\n" +
		"env_key = \"" + inferKeyEnv + "\"\n" +
		"wire_api = \"responses\"\n\n" +
		"[profiles." + localMarker + "]\n" +
		"model = \"" + inferAlias + "\"\n" +
		"model_provider = \"" + localMarker + "\"\n"
}

func codexRewrite(s string, cfg *inferConfig, on bool) string {
	s = tomlRemove(s, "[model_providers."+localMarker+"]")
	s = tomlRemove(s, "[profiles."+localMarker+"]")
	if !on {
		return strings.TrimRight(s, "\n") + map[bool]string{true: "", false: "\n"}[strings.TrimSpace(s) == ""]
	}
	s = strings.TrimRight(s, "\n")
	if s != "" {
		s += "\n\n"
	}
	return s + codexBlock(cfg)
}

func writeKeepMode(f, s string) error {
	mode := os.FileMode(0o600)
	if st, err := os.Stat(f); err == nil {
		mode = st.Mode().Perm()
	}
	os.MkdirAll(filepath.Dir(f), 0o700)
	return writeFileAtomic(f, []byte(s), mode)
}

func wireCodex(cfg *inferConfig, on bool) error {
	f := connectFile("codex")
	b, err := os.ReadFile(f)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	if err != nil && !on {
		return nil
	}
	out := codexRewrite(string(b), cfg, on)
	if out == string(b) {
		return nil
	}
	return writeKeepMode(f, out)
}

func yamlTopValue(s, key string) (string, bool) {
	for _, l := range strings.Split(s, "\n") {
		if strings.HasPrefix(l, key+":") {
			return strings.TrimSpace(strings.TrimPrefix(l, key+":")), true
		}
	}
	return "", false
}

func yamlSetTop(s, key, val string) string {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	if s == "" {
		lines = nil
	}
	for i, l := range lines {
		if strings.HasPrefix(l, key+":") {
			lines[i] = key + ": " + val
			return strings.Join(lines, "\n") + "\n"
		}
	}
	return strings.Join(append(lines, key+": "+val), "\n") + "\n"
}

func yamlDelTop(s, key string) string {
	var out []string
	for _, l := range strings.Split(s, "\n") {
		if strings.HasPrefix(l, key+":") {
			continue
		}
		out = append(out, l)
	}
	return strings.Join(out, "\n")
}

func wireGoose(cfg *inferConfig, rec *connRecord, on bool) error {
	f := connectFile("goose")
	cy := filepath.Join(xdg("XDG_CONFIG_HOME", ".config"), "goose", "config.yaml")
	b, _ := os.ReadFile(cy)
	s := string(b)
	if on {
		prov := map[string]any{
			"name": localMarker, "engine": "openai", "display_name": "KwickOS local (llama.cpp)",
			"description": "Local models served by kwick-agents inference",
			"api_key_env": inferKeyEnv, "base_url": cfg.baseURL() + "/v1",
			"models":             []any{map[string]any{"name": inferAlias, "context_limit": cfg.ctx()}},
			"supports_streaming": true,
		}
		if err := writeJSONKeepMode(f, prov); err != nil {
			return err
		}
		for _, k := range []string{"GOOSE_PROVIDER", "GOOSE_MODEL"} {
			want := localMarker
			if k == "GOOSE_MODEL" {
				want = inferAlias
			}
			if v, ok := yamlTopValue(s, k); ok && strings.Trim(v, `"'`) != want {
				rec.Previous[k] = v
			}
			s = yamlSetTop(s, k, want)
		}
		return writeKeepMode(cy, s)
	}
	os.Remove(f)
	if s == "" {
		return nil
	}
	for _, k := range []string{"GOOSE_PROVIDER", "GOOSE_MODEL"} {
		want := localMarker
		if k == "GOOSE_MODEL" {
			want = inferAlias
		}
		v, ok := yamlTopValue(s, k)
		if !ok || strings.Trim(v, `"'`) != want {
			continue
		}
		if p, ok := rec.Previous[k].(string); ok {
			s = yamlSetTop(s, k, p)
		} else {
			s = yamlDelTop(s, k)
		}
	}
	return writeKeepMode(cy, s)
}

func yamlTopBlock(lines []string, key string) (int, int) {
	start := -1
	for i, l := range lines {
		if l == key+":" || strings.HasPrefix(l, key+":") {
			start = i
			break
		}
	}
	if start < 0 {
		return -1, -1
	}
	end := start + 1
	for end < len(lines) {
		l := lines[end]
		t := strings.TrimSpace(l)
		if t != "" && indentOf(l) == 0 && !strings.HasPrefix(t, "#") {
			break
		}
		end++
	}
	for end > start+1 && strings.TrimSpace(lines[end-1]) == "" {
		end--
	}
	return start, end
}

func hermesBlock(cfg *inferConfig) []string {
	return []string{
		"model:",
		"  # " + localMarker + ": written by kwick-agents inference connect; undo with disconnect",
		"  provider: custom",
		"  default: " + inferAlias,
		"  base_url: " + cfg.baseURL() + "/v1",
		"  api_key: ${" + inferKeyEnv + "}",
	}
}

func hermesRewrite(s string, cfg *inferConfig, rec *connRecord, on bool) string {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	if s == "" {
		lines = nil
	}
	st, en := yamlTopBlock(lines, "model")
	ours := st >= 0 && strings.Contains(strings.Join(lines[st:en], "\n"), "# "+localMarker)
	var repl []string
	if on {
		if st >= 0 && !ours {
			rec.Previous["model_block"] = strings.Join(lines[st:en], "\n")
		}
		repl = hermesBlock(cfg)
	} else {
		if !ours {
			return s
		}
		if p, ok := rec.Previous["model_block"].(string); ok && p != "" {
			repl = strings.Split(p, "\n")
		}
	}
	var out []string
	switch {
	case st >= 0:
		out = append(append(append(out, lines[:st]...), repl...), lines[en:]...)
	case len(lines) > 0 && len(repl) > 0:
		out = append(append(append(out, repl...), ""), lines...)
	default:
		out = append(append(out, repl...), lines...)
	}
	r := strings.Join(out, "\n")
	if strings.TrimSpace(r) == "" {
		return ""
	}
	return r + "\n"
}

func wireHermes(cfg *inferConfig, rec *connRecord, on bool) error {
	f := connectFile("hermes")
	b, err := os.ReadFile(f)
	if err != nil && !on {
		return nil
	}
	out := hermesRewrite(string(b), cfg, rec, on)
	if out == string(b) {
		return nil
	}
	return writeKeepMode(f, out)
}

func wireOpenclaw(cfg *inferConfig, rec *connRecord, on bool) error {
	f := connectFile("openclaw")
	m, _, err := readJSONMap(f)
	if err != nil {
		return err
	}
	if m == nil {
		if !on {
			return nil
		}
		m = map[string]any{}
	}
	if on {
		models, err := ensureMap(m, "models")
		if err != nil {
			return err
		}
		if _, ok := models["mode"]; !ok {
			models["mode"] = "merge"
			rec.Previous["added_mode"] = true
		}
		provs, err := ensureMap(models, "providers")
		if err != nil {
			return err
		}
		provs[localMarker] = map[string]any{
			"baseUrl": cfg.baseURL() + "/v1",
			"apiKey":  "${" + inferKeyEnv + "}",
			"api":     "openai-completions",
			"models":  []any{map[string]any{"id": inferAlias, "name": modelTitle(cfg), "contextWindow": cfg.ctx(), "maxTokens": 8192}},
		}
		agents, err := ensureMap(m, "agents")
		if err != nil {
			return err
		}
		defs, err := ensureMap(agents, "defaults")
		if err != nil {
			return err
		}
		switch cur := defs["model"].(type) {
		case map[string]any:
			if p, ok := cur["primary"]; ok && p != localModelRef {
				rec.Previous["primary"] = p
			}
			cur["primary"] = localModelRef
		case nil:
			defs["model"] = map[string]any{"primary": localModelRef}
		default:
			rec.Previous["model"] = cur
			defs["model"] = map[string]any{"primary": localModelRef}
		}
	} else {
		if models, ok := m["models"].(map[string]any); ok {
			if provs, ok := models["providers"].(map[string]any); ok {
				delete(provs, localMarker)
				if len(provs) == 0 {
					delete(models, "providers")
				}
			}
			if rec.Previous["added_mode"] == true && len(models) == 1 && models["mode"] == "merge" {
				delete(m, "models")
			}
		}
		if defs, ok := jsonGet(m, []string{"agents", "defaults"}); ok {
			if dm, ok := defs.(map[string]any); ok {
				if mm, ok := dm["model"].(map[string]any); ok && mm["primary"] == localModelRef {
					if p, ok := rec.Previous["model"]; ok {
						dm["model"] = p
					} else if p, ok := rec.Previous["primary"]; ok {
						mm["primary"] = p
					} else {
						delete(mm, "primary")
						if len(mm) == 0 {
							delete(dm, "model")
						}
					}
				}
				if len(dm) == 0 {
					if ag, ok := m["agents"].(map[string]any); ok {
						delete(ag, "defaults")
						if len(ag) == 0 {
							delete(m, "agents")
						}
					}
				}
			}
		}
	}
	return writeJSONKeepMode(f, m)
}

func yamlChildValue(s, top, child string) (string, bool) {
	lines := strings.Split(s, "\n")
	t, _ := yamlTop(lines, top)
	if t < 0 {
		return "", false
	}
	start, end, ind := yamlChildren(lines, t)
	pfx := strings.Repeat(" ", ind) + child + ":"
	for _, l := range lines[start:end] {
		if strings.HasPrefix(l, pfx) {
			return strings.TrimSpace(l[len(pfx):]), true
		}
	}
	return "", false
}

func yamlSetChild(s, top, child, val string) string {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	if s == "" {
		lines = nil
	}
	t, _ := yamlTop(lines, top)
	if t < 0 {
		if len(lines) > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, top+":", "  "+child+": "+val)
		return strings.Join(lines, "\n") + "\n"
	}
	lines[t] = top + ":"
	start, end, ind := yamlChildren(lines, t)
	pfx := strings.Repeat(" ", ind) + child + ":"
	for i := start; i < end; i++ {
		if strings.HasPrefix(lines[i], pfx) {
			lines[i] = pfx + " " + val
			return strings.Join(lines, "\n") + "\n"
		}
	}
	at := end
	for at > t+1 && strings.TrimSpace(lines[at-1]) == "" {
		at--
	}
	rest := append([]string{}, lines[at:]...)
	lines = append(append(lines[:at], pfx+" "+val), rest...)
	return strings.Join(lines, "\n") + "\n"
}

func ompModelsBody(cfg *inferConfig) []string {
	return []string{
		"baseUrl: " + cfg.baseURL() + "/v1",
		"api: openai-completions",
		"apiKey: " + inferKeyEnv,
		"models:",
		"  - id: " + inferAlias,
		"    name: " + inferAlias,
		fmt.Sprintf("    contextWindow: %d", cfg.ctx()),
		"    maxTokens: 8192",
	}
}

func wireOmp(cfg *inferConfig, rec *connRecord, on bool) error {
	f := connectFile("omp")
	cf := filepath.Join(filepath.Dir(f), "config.yml")
	b, _ := os.ReadFile(f)
	s := yamlRemoveChild(string(b), "providers", localMarker)
	cb, _ := os.ReadFile(cf)
	cs := string(cb)
	if on {
		s = yamlAddChild(strings.TrimSuffix(s, "providers: {}\n"), "providers", localMarker, ompModelsBody(cfg))
		if v, ok := yamlChildValue(cs, "modelRoles", "default"); ok && v != localModelRef {
			rec.Previous["default"] = v
		}
		cs = yamlSetChild(cs, "modelRoles", "default", localModelRef)
	} else {
		if v, ok := yamlChildValue(cs, "modelRoles", "default"); ok && v == localModelRef {
			if p, ok := rec.Previous["default"].(string); ok {
				cs = yamlSetChild(cs, "modelRoles", "default", p)
			} else {
				cs = yamlRemoveChild(cs, "modelRoles", "default")
			}
		}
	}
	if s != "" && !strings.HasSuffix(s, "\n") {
		s += "\n"
	}
	if s != string(b) && (on || len(b) > 0) {
		if err := writeKeepMode(f, s); err != nil {
			return err
		}
	}
	if cs != string(cb) {
		return writeKeepMode(cf, cs)
	}
	return nil
}

func cybaraBase() string {
	if v := os.Getenv("CYBARA_API"); strings.HasPrefix(v, "http://") || strings.HasPrefix(v, "https://") {
		return strings.TrimRight(v, "/")
	}
	return "http://localhost:4269"
}

func cybaraToken() string {
	if v := strings.TrimSpace(os.Getenv("CYBARA_API_KEY")); v != "" {
		return v
	}
	home := os.Getenv("CYBARA_HOME")
	if home == "" {
		home = filepath.Join(homeDir(), ".cybara")
	}
	return readTrim(filepath.Join(home, "api_key"))
}

var cybaraClient = &http.Client{Timeout: 20 * time.Second}

func cybaraCall(method, p string, body any) ([]byte, int, error) {
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, cybaraBase()+p, rd)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	if t := cybaraToken(); t != "" {
		req.Header.Set("Authorization", "Bearer "+t)
	}
	resp, err := cybaraClient.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	return b, resp.StatusCode, err
}

type cybaraProvider struct {
	ID        string `json:"id"`
	Provider  string `json:"provider"`
	Name      string `json:"name"`
	IsDefault bool   `json:"is_default"`
}

func cybaraUnreachable(err error) error {
	return fmt.Errorf("Cybara's gateway does not answer at %s (%v). Start it with 'cybara start' and run 'kwick-agents inference connect cybara' again. "+
		"By hand: Settings > Providers > Custom, base URL %s, model %q, key from $%s; %s describes the endpoint",
		cybaraBase(), err, loadInferConfig().baseURL()+"/v1", inferAlias, inferKeyEnv, shortPath(endpointPath()))
}

func wireCybara(cfg *inferConfig, rec *connRecord, on bool) error {
	b, code, err := cybaraCall("GET", "/api/providers", nil)
	if err != nil {
		return cybaraUnreachable(err)
	}
	if code == 401 || code == 403 {
		return fmt.Errorf("Cybara's gateway refused the request (%d); kwick-agents reads Cybara's API key from $CYBARA_API_KEY or ~/.cybara/api_key", code)
	}
	if code != 200 {
		return fmt.Errorf("Cybara's gateway answered %d: %s", code, strings.TrimSpace(string(b)))
	}
	var list []cybaraProvider
	if err := json.Unmarshal(b, &list); err != nil {
		var wrap struct {
			Providers []cybaraProvider `json:"providers"`
		}
		if json.Unmarshal(b, &wrap) != nil {
			return fmt.Errorf("unexpected answer from Cybara's gateway")
		}
		list = wrap.Providers
	}
	var ours *cybaraProvider
	prevDefault := ""
	for i := range list {
		p := &list[i]
		if p.Name == cybaraName || (rec.ID != "" && p.ID == rec.ID) {
			ours = p
		} else if p.IsDefault {
			prevDefault = p.ID
		}
	}
	if !on {
		if ours == nil {
			return nil
		}
		if b, code, err := cybaraCall("DELETE", "/api/providers/"+ours.ID, nil); err != nil || code >= 300 {
			return fmt.Errorf("could not remove the provider from Cybara: %v %s", err, strings.TrimSpace(string(b)))
		}
		if p, ok := rec.Previous["default_provider"].(string); ok && p != "" && ours.IsDefault {
			cybaraCall("PUT", "/api/providers/"+p, map[string]any{"is_default": true})
		}
		return nil
	}
	key, err := inferKey(true)
	if err != nil {
		return err
	}
	if prevDefault != "" {
		rec.Previous["default_provider"] = prevDefault
	}
	body := map[string]any{"name": cybaraName, "base_url": cfg.baseURL() + "/v1", "api_key": key, "is_default": true}
	if ours != nil {
		b, code, err := cybaraCall("PUT", "/api/providers/"+ours.ID, body)
		if err != nil || code >= 300 {
			return fmt.Errorf("could not update the provider in Cybara: %v %s", err, strings.TrimSpace(string(b)))
		}
		rec.ID = ours.ID
	} else {
		body["provider"] = "custom"
		b, code, err := cybaraCall("POST", "/api/providers", body)
		if err != nil || code >= 300 {
			return fmt.Errorf("could not add the provider to Cybara: %v %s", err, strings.TrimSpace(string(b)))
		}
		var r struct {
			ID    string `json:"id"`
			Error string `json:"error"`
		}
		json.Unmarshal(b, &r)
		if r.ID == "" {
			return fmt.Errorf("Cybara did not add the provider: %s", r.Error)
		}
		rec.ID = r.ID
	}
	if _, code, err := cybaraCall("POST", "/api/providers/"+rec.ID+"/models/discover", map[string]any{}); err != nil || code >= 300 {
		say("Cybara could not list the local models yet (is the endpoint running?); it lists them when you pick the provider")
	}
	return nil
}

var localRun bool

func takeLocalFlag(a []string) []string {
	if len(a) == 0 || a[0] != "run" {
		return a
	}
	out := make([]string, 0, len(a))
	done := false
	for i, s := range a {
		if s == "--" {
			out = append(out, a[i:]...)
			break
		}
		if s == "--local" && !done {
			localRun = true
			done = true
			continue
		}
		out = append(out, s)
	}
	return out
}

func applyLocalRun(e *Entry, m map[string]string) {
	if !localRun {
		return
	}
	cfg := loadInferConfig()
	key := m[inferKeyEnv]
	if key == "" {
		warnf("--local: no %s in the keystore yet; start the endpoint first: kwick-agents inference service start", inferKeyEnv)
	} else if !healthy(cfg, key) {
		warnf("--local: the local endpoint %s does not answer; start it with: kwick-agents inference service start", cfg.baseURL())
	}
	base := cfg.baseURL()
	switch e.Name {
	case "aider":
		m["OPENAI_API_BASE"] = base + "/v1"
		m["OPENAI_API_KEY"] = key
		m["AIDER_MODEL"] = "openai/" + inferAlias
		m["AIDER_SHOW_MODEL_WARNINGS"] = "false"
	case "claude-code":
		fmt.Fprintln(os.Stderr, "kwick-agents: WARNING: Claude Code is made for Claude models. Anthropic does not support running it against other models;")
		fmt.Fprintln(os.Stderr, "kwick-agents: tool use and long tasks may fail. This run uses the local model \""+inferAlias+"\" ("+cfg.Model+") at "+base+".")
		delete(m, "ANTHROPIC_API_KEY")
		m["ANTHROPIC_BASE_URL"] = base
		m["ANTHROPIC_AUTH_TOKEN"] = key
		for _, k := range []string{"ANTHROPIC_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL"} {
			m[k] = inferAlias
		}
		m["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
		m["CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS"] = "1"
	default:
		m["OPENAI_BASE_URL"] = base + "/v1"
		m["OPENAI_API_BASE"] = base + "/v1"
		m["OPENAI_API_KEY"] = key
		m["OPENAI_MODEL"] = inferAlias
		if _, ok := connectMethod[e.Name]; ok && connectMethod[e.Name] == "config" {
			fmt.Fprintf(os.Stderr, "kwick-agents: %s reads its provider from its own config; run 'kwick-agents inference connect %s' once\n", e.Name, e.Name)
		}
	}
	m["KWICK_INFERENCE_URL"] = base + "/v1"
	m["KWICK_INFERENCE_MODEL"] = inferAlias
}
