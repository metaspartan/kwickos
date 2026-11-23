package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func testHome(t *testing.T) (string, string) {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	t.Setenv("XDG_STATE_HOME", filepath.Join(home, ".local/state"))
	t.Setenv("XDG_DATA_HOME", filepath.Join(home, ".local/share"))
	t.Setenv("XDG_RUNTIME_DIR", filepath.Join(home, "run"))
	os.MkdirAll(filepath.Join(home, "run"), 0o700)
	proj := filepath.Join(home, "proj")
	if err := os.MkdirAll(proj, 0o755); err != nil {
		t.Fatal(err)
	}
	return home, proj
}

func writeTool(s *Server, path, content, mode string) (toolResult, error) {
	a := map[string]any{"path": path, "content": content}
	if mode != "" {
		a["mode"] = mode
	}
	return toolFilesWrite(s, a)
}

func TestWriteThroughDanglingSymlinkIsRefused(t *testing.T) {
	home, proj := testHome(t)
	outside := filepath.Join(home, "outside")
	os.MkdirAll(outside, 0o755)
	target := filepath.Join(outside, "pwned.txt")
	if err := os.Symlink(target, filepath.Join(proj, "link.txt")); err != nil {
		t.Fatal(err)
	}
	s := newServer("test", []string{proj}, false)
	for _, mode := range []string{"", "create", "append", "overwrite"} {
		if _, err := writeTool(s, "link.txt", "x", mode); err == nil {
			t.Fatalf("mode %q: write through a dangling symlink was allowed", mode)
		}
		if exists(target) {
			t.Fatalf("mode %q: file created outside the project", mode)
		}
	}
}

func TestWriteThroughSymlinkedParentIsRefused(t *testing.T) {
	home, proj := testHome(t)
	outside := filepath.Join(home, "outside")
	os.MkdirAll(outside, 0o755)
	if err := os.Symlink(outside, filepath.Join(proj, "dir")); err != nil {
		t.Fatal(err)
	}
	s := newServer("test", []string{proj}, false)
	if _, err := writeTool(s, "dir/new.txt", "x", ""); err == nil {
		t.Fatal("write through a symlinked folder that leaves the project was allowed")
	}
	if exists(filepath.Join(outside, "new.txt")) {
		t.Fatal("file created outside the project")
	}
}

func TestWriteBelowRootFollowsResolvedPathOnly(t *testing.T) {
	home, proj := testHome(t)
	_ = home
	s := newServer("test", []string{proj}, false)
	r, err := writeTool(s, "sub/dir/a.txt", "hello", "create")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(filepath.Join(proj, "sub/dir/a.txt"))
	if string(b) != "hello" {
		t.Fatalf("content %q", b)
	}
	if _, err := writeTool(s, "sub/dir/a.txt", " world", "append"); err != nil {
		t.Fatal(err)
	}
	if _, err := writeTool(s, "sub/dir/a.txt", "x", "create"); err == nil {
		t.Fatal("create over an existing file was allowed")
	}
	if _, err := writeTool(s, "sub/dir/a.txt", "new", "overwrite"); err != nil {
		t.Fatal(err)
	}
	b, _ = os.ReadFile(filepath.Join(proj, "sub/dir/a.txt"))
	if string(b) != "new" {
		t.Fatalf("overwrite left %q", b)
	}
	if r.Data == nil {
		t.Fatal("no data")
	}
	os.Symlink(filepath.Join(proj, "sub/dir/a.txt"), filepath.Join(proj, "inside-link"))
	if _, err := writeTool(s, "inside-link", "via link", ""); err != nil {
		t.Fatalf("symlink to a file inside the project: %v", err)
	}
	b, _ = os.ReadFile(filepath.Join(proj, "sub/dir/a.txt"))
	if string(b) != "via link" {
		t.Fatalf("got %q", b)
	}
}

func TestKwickAgentsOwnDirsAreNeverWritable(t *testing.T) {
	home, _ := testHome(t)
	u := userScope()
	for _, d := range []string{u.Config, u.State, u.Data} {
		os.MkdirAll(d, 0o700)
	}
	grants := filepath.Join(u.Config, "grants.json")
	os.WriteFile(grants, []byte(`{"schema":1,"agents":{}}`), 0o600)
	s := newServer("test", []string{home}, false)
	for _, p := range []string{
		grants,
		filepath.Join(u.Config, "agents", "test.json"),
		filepath.Join(u.State, "audit.jsonl"),
		filepath.Join(u.Data, "home", "test", ".bashrc"),
		filepath.Join(runtimeDir(), "pending", "x.answer"),
		filepath.Join(runtimeDir(), "control", "x.json"),
		"~/.config/kwick-agents/keys.json",
	} {
		if _, err := writeTool(s, p, `{"schema":1,"agents":{"test":{"caps":{"packages.manage":"allow"}}}}`, ""); err == nil || !strings.Contains(err.Error(), "kwick-agents") {
			t.Fatalf("write to %s: %v", p, err)
		}
		if err := (toolByName("files_write")).precheck(s, map[string]any{"path": p, "content": "x"}); err == nil {
			t.Fatalf("precheck allowed %s", p)
		}
	}
	b, _ := os.ReadFile(grants)
	if strings.Contains(string(b), "allow") {
		t.Fatal("grants.json was changed")
	}
	os.Symlink(grants, filepath.Join(home, "innocent.json"))
	if _, err := writeTool(s, "~/innocent.json", "{}", ""); err == nil {
		t.Fatal("write through a symlink into the kwick-agents config was allowed")
	}
	os.Symlink(u.Config, filepath.Join(home, "cfg"))
	if _, err := writeTool(s, "~/cfg/grants.json", "{}", ""); err == nil {
		t.Fatal("write through a symlinked folder into the kwick-agents config was allowed")
	}
	if _, err := writeTool(s, "~/notes.txt", "ok", ""); err != nil {
		t.Fatalf("ordinary write in a granted home: %v", err)
	}
}

func TestSecretsAreNotReadable(t *testing.T) {
	home, _ := testHome(t)
	u := userScope()
	os.MkdirAll(u.Config, 0o700)
	sec := filepath.Join(u.Config, "secrets.json")
	os.WriteFile(sec, []byte(`{"k":"sk-secret"}`), 0o600)
	s := newServer("test", []string{home}, false)
	if r, err := toolFilesRead(s, map[string]any{"path": sec}); err == nil {
		t.Fatalf("secrets.json was readable: %v", r.Text)
	}
	os.Symlink(sec, filepath.Join(home, "s.json"))
	if _, err := toolFilesRead(s, map[string]any{"path": "~/s.json"}); err == nil {
		t.Fatal("secrets.json was readable through a symlink")
	}
	os.WriteFile(filepath.Join(u.Config, "grants.json"), []byte(`{}`), 0o600)
	if _, err := toolFilesRead(s, map[string]any{"path": filepath.Join(u.Config, "grants.json")}); err != nil {
		t.Fatalf("reading grants.json should stay possible: %v", err)
	}
}

func TestReadOutsideRootsRefused(t *testing.T) {
	home, proj := testHome(t)
	os.WriteFile(filepath.Join(home, "private.txt"), []byte("secret"), 0o600)
	os.Symlink(filepath.Join(home, "private.txt"), filepath.Join(proj, "p"))
	s := newServer("test", []string{proj}, false)
	if _, err := toolFilesRead(s, map[string]any{"path": "p"}); err == nil {
		t.Fatal("read through a symlink to outside the project was allowed")
	}
	os.WriteFile(filepath.Join(proj, "ok.txt"), []byte("fine"), 0o644)
	r, err := toolFilesRead(s, map[string]any{"path": "ok.txt"})
	if err != nil || r.Text != "fine" {
		t.Fatalf("read inside project: %v %q", err, r.Text)
	}
	lr, err := toolFilesList(s, map[string]any{})
	if err != nil {
		t.Fatal(err)
	}
	if lr.Data.(map[string]any)["path"] != proj {
		t.Fatalf("list path %v", lr.Data)
	}
}

func toolByName(n string) tool {
	for _, t := range toolTable() {
		if t.Name == n {
			return t
		}
	}
	return tool{}
}
