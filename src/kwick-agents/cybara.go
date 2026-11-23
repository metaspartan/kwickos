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

const cybaraServerName = "KwickOS: " + mcpKey

func cybaraHome() string {
	if h := strings.TrimSpace(os.Getenv("CYBARA_HOME")); h != "" && filepath.IsAbs(h) {
		return h
	}
	if b, err := os.ReadFile(filepath.Join(homeDir(), ".cybara_home")); err == nil {
		if h := strings.TrimSpace(string(b)); h != "" {
			h = expandHome(h)
			if filepath.IsAbs(h) {
				return h
			}
		}
	}
	return filepath.Join(homeDir(), ".cybara")
}

func cybaraPluginDir() string { return filepath.Join(cybaraHome(), "plugins", mcpKey) }

func cybaraEnable() error {
	d := cybaraPluginDir()
	if err := os.MkdirAll(d, 0o700); err != nil {
		return err
	}
	manifest := map[string]any{
		"schemaVersion": 1, "id": mcpKey, "name": "KwickOS", "version": "1.0.0",
		"description":   "KwickOS system tools with permissions and an audit log (kwick-mcp): settings, apps, files, packages, snapshots and computer use",
		"contributions": map[string]any{"mcpServers": map[string]any{"files": []string{"mcp.json"}}},
	}
	servers := []map[string]any{{"name": mcpKey, "command": mcpPath, "enabled": true}}
	if err := writeJSONFile(filepath.Join(d, "mcp.json"), servers, 0o600); err != nil {
		return err
	}
	if err := writeJSONFile(filepath.Join(d, "cybara-plugin.json"), manifest, 0o600); err != nil {
		return err
	}
	cybaraStartServer(3 * time.Second)
	return nil
}

func cybaraAPI() string {
	if u := strings.TrimRight(os.Getenv("CYBARA_API"), "/"); strings.HasPrefix(u, "http://127.0.0.1:") || strings.HasPrefix(u, "http://localhost:") {
		return u
	}
	return "http://127.0.0.1:4269"
}

func cybaraRequest(method, path string, timeout time.Duration) ([]byte, error) {
	req, err := http.NewRequest(method, cybaraAPI()+path, bytes.NewReader(nil))
	if err != nil {
		return nil, err
	}
	key := strings.TrimSpace(os.Getenv("CYBARA_API_KEY"))
	if key == "" {
		if b, err := os.ReadFile(filepath.Join(cybaraHome(), "api_key")); err == nil {
			key = strings.TrimSpace(string(b))
		}
	}
	if key != "" {
		req.Header.Set("Authorization", "Bearer "+key)
	}
	if method == "POST" {
		req.Header.Set("Content-Type", "application/json")
	}
	cl := &http.Client{Timeout: timeout, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	resp, err := cl.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if resp.StatusCode/100 != 2 {
		return b, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	return b, nil
}

func cybaraStartServer(timeout time.Duration) (bool, error) {
	b, err := cybaraRequest("GET", "/api/mcp", timeout)
	if err != nil {
		return false, err
	}
	var list []struct {
		ID     string `json:"id"`
		Name   string `json:"name"`
		Status string `json:"status"`
	}
	if err := json.Unmarshal(b, &list); err != nil {
		var wrapped struct {
			Servers []struct {
				ID     string `json:"id"`
				Name   string `json:"name"`
				Status string `json:"status"`
			} `json:"servers"`
		}
		if json.Unmarshal(b, &wrapped) != nil {
			return false, fmt.Errorf("unexpected answer from the Cybara gateway")
		}
		for _, s := range wrapped.Servers {
			list = append(list, s)
		}
	}
	for _, s := range list {
		if s.Name != cybaraServerName {
			continue
		}
		if s.Status == "running" {
			return true, nil
		}
		if strings.ContainsAny(s.ID, "/?#") {
			return false, fmt.Errorf("bad server id")
		}
		_, err := cybaraRequest("POST", "/api/mcp/"+s.ID+"/start", 30*time.Second)
		return err == nil, err
	}
	return false, fmt.Errorf("the gateway has not loaded the KwickOS plugin yet")
}

func cybaraAutoStart(done <-chan struct{}) {
	deadline := time.Now().Add(3 * time.Minute)
	for time.Now().Before(deadline) {
		select {
		case <-done:
			return
		case <-time.After(3 * time.Second):
		}
		if ok, _ := cybaraStartServer(3 * time.Second); ok {
			auditLog(auditEntry{Agent: "cybara", Tool: "mcp", Decision: "start", OK: true, Summary: "started kwick-mcp in the Cybara gateway"})
			return
		}
	}
}
