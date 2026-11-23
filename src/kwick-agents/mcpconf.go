package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

const mcpKey = "kwickos"

type jsonTarget struct {
	file    string
	path    []string
	value   map[string]any
	newFile map[string]any
}

func mcpJSONTarget(e *Entry) *jsonTarget {
	h := homeDir()
	switch e.MCP {
	case "claude":
		return &jsonTarget{file: filepath.Join(h, ".claude.json"), path: []string{"mcpServers", mcpKey},
			value: map[string]any{"type": "stdio", "command": mcpPath, "args": []any{}, "env": map[string]any{}}}
	case "gemini":
		return &jsonTarget{file: filepath.Join(h, ".gemini", "settings.json"), path: []string{"mcpServers", mcpKey},
			value: map[string]any{"command": mcpPath, "args": []any{}}}
	case "omp":
		return &jsonTarget{file: filepath.Join(h, ".omp", "agent", "mcp.json"), path: []string{"mcpServers", mcpKey},
			value: map[string]any{"type": "stdio", "command": mcpPath, "args": []any{}}}
	case "opencode":
		return &jsonTarget{file: filepath.Join(xdg("XDG_CONFIG_HOME", ".config"), "opencode", "opencode.json"), path: []string{"mcp", mcpKey},
			value:   map[string]any{"type": "local", "command": []any{mcpPath}, "enabled": true},
			newFile: map[string]any{"$schema": "https://opencode.ai/config.json"}}
	case "openclaw":
		return &jsonTarget{file: filepath.Join(h, ".openclaw", "openclaw.json"), path: []string{"mcp", "servers", mcpKey},
			value: map[string]any{"command": mcpPath, "args": []any{}}}
	}
	return nil
}

func mcpConfigFile(e *Entry) string {
	if t := mcpJSONTarget(e); t != nil {
		return t.file
	}
	h := homeDir()
	switch e.MCP {
	case "codex":
		return filepath.Join(h, ".codex", "config.toml")
	case "goose":
		return filepath.Join(xdg("XDG_CONFIG_HOME", ".config"), "goose", "config.yaml")
	case "hermes":
		return filepath.Join(h, ".hermes", "config.yaml")
	case "cybara":
		return filepath.Join(cybaraPluginDir(), "cybara-plugin.json")
	}
	return ""
}

func readJSONMap(file string) (map[string]any, bool, error) {
	b, err := os.ReadFile(file)
	if os.IsNotExist(err) {
		return nil, false, nil
	}
	if err != nil {
		return nil, true, err
	}
	if len(strings.TrimSpace(string(b))) == 0 {
		return map[string]any{}, true, nil
	}
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, true, fmt.Errorf("%s is not plain JSON (%v); add kwick-mcp by hand: command %s", shortPath(file), err, mcpPath)
	}
	return m, true, nil
}

func jsonGet(m map[string]any, path []string) (any, bool) {
	var cur any = m
	for _, k := range path {
		mm, ok := cur.(map[string]any)
		if !ok {
			return nil, false
		}
		cur, ok = mm[k]
		if !ok {
			return nil, false
		}
	}
	return cur, true
}

func writeJSONKeepMode(file string, m map[string]any) error {
	mode := os.FileMode(0o600)
	if st, err := os.Stat(file); err == nil {
		mode = st.Mode().Perm()
	}
	os.MkdirAll(filepath.Dir(file), 0o700)
	b, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	return writeFileAtomic(file, append(b, '\n'), mode)
}

var (
	tomlHeader = "[mcp_servers." + mcpKey + "]"
)

func mcpConfigured(e *Entry) bool {
	if t := mcpJSONTarget(e); t != nil {
		m, _, err := readJSONMap(t.file)
		if err != nil || m == nil {
			return false
		}
		_, ok := jsonGet(m, t.path)
		return ok
	}
	f := mcpConfigFile(e)
	if f == "" {
		return false
	}
	b, err := os.ReadFile(f)
	if err != nil {
		return false
	}
	switch e.MCP {
	case "cybara":
		m, err := os.ReadFile(filepath.Join(cybaraPluginDir(), "mcp.json"))
		return err == nil && strings.Contains(string(m), mcpPath)
	case "codex":
		return strings.Contains(string(b), tomlHeader)
	case "goose":
		return yamlHasChild(string(b), "extensions", mcpKey)
	case "hermes":
		return yamlHasChild(string(b), "mcp_servers", mcpKey)
	}
	return false
}

func mcpEnable(e *Entry) (string, error) {
	if t := mcpJSONTarget(e); t != nil {
		m, existed, err := readJSONMap(t.file)
		if err != nil {
			return "", err
		}
		if m == nil {
			m = map[string]any{}
			for k, v := range t.newFile {
				m[k] = v
			}
		}
		_ = existed
		cur := m
		for _, k := range t.path[:len(t.path)-1] {
			next, ok := cur[k].(map[string]any)
			if !ok {
				if _, present := cur[k]; present {
					return "", fmt.Errorf("%s: %q is not an object; add kwick-mcp by hand", shortPath(t.file), k)
				}
				next = map[string]any{}
				cur[k] = next
			}
			cur = next
		}
		cur[t.path[len(t.path)-1]] = t.value
		return t.file, writeJSONKeepMode(t.file, m)
	}
	f := mcpConfigFile(e)
	if f == "" {
		return "", nil
	}
	if e.MCP == "cybara" {
		return f, cybaraEnable()
	}
	b, _ := os.ReadFile(f)
	s := string(b)
	var out string
	switch e.MCP {
	case "codex":
		if strings.Contains(s, tomlHeader) {
			return f, nil
		}
		if s != "" && !strings.HasSuffix(s, "\n") {
			s += "\n"
		}
		if s != "" {
			s += "\n"
		}
		out = s + tomlHeader + "\ncommand = \"" + mcpPath + "\"\nargs = []\n"
	case "goose":
		out = yamlAddChild(s, "extensions", mcpKey, []string{
			"name: KwickOS", "cmd: " + mcpPath, "args: []", "enabled: true", "type: stdio", "timeout: 300",
			"description: KwickOS system tools with permissions and an audit log"})
	case "hermes":
		out = yamlAddChild(s, "mcp_servers", mcpKey, []string{"command: \"" + mcpPath + "\"", "args: []"})
	default:
		return "", nil
	}
	mode := os.FileMode(0o600)
	if st, err := os.Stat(f); err == nil {
		mode = st.Mode().Perm()
	}
	os.MkdirAll(filepath.Dir(f), 0o700)
	return f, writeFileAtomic(f, []byte(out), mode)
}

func mcpDisable(e *Entry) (string, error) {
	if t := mcpJSONTarget(e); t != nil {
		m, _, err := readJSONMap(t.file)
		if err != nil || m == nil {
			return t.file, err
		}
		if _, ok := jsonGet(m, t.path); !ok {
			return t.file, nil
		}
		parent, _ := jsonGet(m, t.path[:len(t.path)-1])
		if pm, ok := parent.(map[string]any); ok {
			delete(pm, t.path[len(t.path)-1])
		}
		return t.file, writeJSONKeepMode(t.file, m)
	}
	f := mcpConfigFile(e)
	if f == "" {
		return "", nil
	}
	if e.MCP == "cybara" {
		return f, os.RemoveAll(cybaraPluginDir())
	}
	b, err := os.ReadFile(f)
	if err != nil {
		return f, nil
	}
	s := string(b)
	var out string
	switch e.MCP {
	case "codex":
		out = tomlRemove(s, tomlHeader)
	case "goose":
		out = yamlRemoveChild(s, "extensions", mcpKey)
	case "hermes":
		out = yamlRemoveChild(s, "mcp_servers", mcpKey)
	default:
		return "", nil
	}
	if out == s {
		return f, nil
	}
	st, _ := os.Stat(f)
	return f, writeFileAtomic(f, []byte(out), st.Mode().Perm())
}

func tomlRemove(s, header string) string {
	lines := strings.Split(s, "\n")
	var out []string
	skip := false
	for _, l := range lines {
		t := strings.TrimSpace(l)
		if t == header {
			skip = true
			continue
		}
		if skip && strings.HasPrefix(t, "[") {
			skip = false
		}
		if !skip {
			out = append(out, l)
		}
	}
	r := strings.Join(out, "\n")
	for strings.Contains(r, "\n\n\n") {
		r = strings.ReplaceAll(r, "\n\n\n", "\n\n")
	}
	return r
}

func indentOf(l string) int { return len(l) - len(strings.TrimLeft(l, " ")) }

func yamlTop(lines []string, key string) (int, *regexp.Regexp) {
	re := regexp.MustCompile(`^` + regexp.QuoteMeta(key) + `:\s*(\{\s*\}|\[\s*\])?\s*(#.*)?$`)
	for i, l := range lines {
		if re.MatchString(l) {
			return i, re
		}
	}
	return -1, re
}

func yamlChildren(lines []string, top int) (int, int, int) {
	end := top + 1
	ind := 0
	for end < len(lines) {
		l := lines[end]
		if strings.TrimSpace(l) == "" || strings.HasPrefix(strings.TrimSpace(l), "#") {
			end++
			continue
		}
		if indentOf(l) == 0 {
			break
		}
		if ind == 0 {
			ind = indentOf(l)
		}
		end++
	}
	if ind == 0 {
		ind = 2
	}
	return top + 1, end, ind
}

func yamlHasChild(s, top, child string) bool {
	lines := strings.Split(s, "\n")
	t, _ := yamlTop(lines, top)
	if t < 0 {
		return false
	}
	start, end, ind := yamlChildren(lines, t)
	pfx := strings.Repeat(" ", ind) + child + ":"
	for _, l := range lines[start:end] {
		if strings.HasPrefix(l, pfx) {
			return true
		}
	}
	return false
}

func yamlAddChild(s, top, child string, body []string) string {
	if yamlHasChild(s, top, child) {
		return s
	}
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	if s == "" {
		lines = nil
	}
	t, _ := yamlTop(lines, top)
	ind := 2
	at := len(lines)
	if t >= 0 {
		lines[t] = top + ":"
		_, end, i := yamlChildren(lines, t)
		ind = i
		at = end
		for at > t+1 && strings.TrimSpace(lines[at-1]) == "" {
			at--
		}
	}
	pad := strings.Repeat(" ", ind)
	block := []string{pad + child + ":"}
	for _, b := range body {
		block = append(block, pad+pad+b)
	}
	if t < 0 {
		if len(lines) > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, top+":")
		lines = append(lines, block...)
	} else {
		rest := append([]string{}, lines[at:]...)
		lines = append(append(lines[:at], block...), rest...)
	}
	return strings.Join(lines, "\n") + "\n"
}

func yamlRemoveChild(s, top, child string) string {
	lines := strings.Split(s, "\n")
	t, _ := yamlTop(lines, top)
	if t < 0 {
		return s
	}
	start, end, ind := yamlChildren(lines, t)
	pfx := strings.Repeat(" ", ind) + child + ":"
	var out []string
	out = append(out, lines[:start]...)
	skip := false
	for _, l := range lines[start:end] {
		if strings.HasPrefix(l, pfx) {
			skip = true
			continue
		}
		if skip {
			if strings.TrimSpace(l) == "" || indentOf(l) > ind {
				continue
			}
			skip = false
		}
		out = append(out, l)
	}
	out = append(out, lines[end:]...)
	hasChild := false
	for _, l := range out[t+1:] {
		if strings.TrimSpace(l) == "" {
			continue
		}
		hasChild = indentOf(l) > 0
		break
	}
	if !hasChild {
		out[t] = top + ": {}"
	}
	return strings.Join(out, "\n")
}
