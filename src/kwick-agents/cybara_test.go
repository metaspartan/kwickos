package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestCybaraRegistration(t *testing.T) {
	home, _ := testHome(t)
	t.Setenv("CYBARA_HOME", "")
	t.Setenv("CYBARA_API", "http://127.0.0.1:1")
	e := &Entry{Name: "cybara", MCP: "cybara"}
	if mcpConfigured(e) {
		t.Fatal("configured before enable")
	}
	f, err := mcpEnable(e)
	if err != nil {
		t.Fatal(err)
	}
	if f != filepath.Join(home, ".cybara", "plugins", "kwickos", "cybara-plugin.json") {
		t.Fatalf("file %s", f)
	}
	var man map[string]any
	if err := readJSONFile(f, &man); err != nil {
		t.Fatal(err)
	}
	if man["id"] != "kwickos" || man["name"] != "KwickOS" || man["schemaVersion"] != float64(1) {
		t.Fatalf("manifest %v", man)
	}
	b, _ := os.ReadFile(filepath.Join(filepath.Dir(f), "mcp.json"))
	var servers []map[string]any
	if err := json.Unmarshal(b, &servers); err != nil || len(servers) != 1 || servers[0]["command"] != mcpPath || servers[0]["name"] != "kwickos" {
		t.Fatalf("mcp.json %s", b)
	}
	if !mcpConfigured(e) {
		t.Fatal("not configured after enable")
	}
	if _, err := mcpDisable(e); err != nil {
		t.Fatal(err)
	}
	if mcpConfigured(e) || exists(filepath.Dir(f)) {
		t.Fatal("still configured after disable")
	}
	t.Setenv("CYBARA_HOME", filepath.Join(home, "elsewhere"))
	if cybaraPluginDir() != filepath.Join(home, "elsewhere", "plugins", "kwickos") {
		t.Fatalf("CYBARA_HOME ignored: %s", cybaraPluginDir())
	}
}
