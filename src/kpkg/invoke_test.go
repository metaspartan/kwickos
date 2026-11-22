package main

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestReadAptConfLists(t *testing.T) {
	out := map[string][]string{}
	readAptConfLists(`// snapshots
DPkg::Pre-Invoke { "[ -x /usr/sbin/kwick-snapshot ] && /usr/sbin/kwick-snapshot apt-pre || true"; };
DPkg { Post-Invoke { "one"; "two"; }; };
DPkg::Post-Invoke:: "three";
APT::Default-Release "trixie";
`, out)
	if got := out["dpkg::pre-invoke"]; !reflect.DeepEqual(got, []string{"[ -x /usr/sbin/kwick-snapshot ] && /usr/sbin/kwick-snapshot apt-pre || true"}) {
		t.Fatalf("pre-invoke = %q", got)
	}
	if got := out["dpkg::post-invoke"]; !reflect.DeepEqual(got, []string{"one", "two", "three"}) {
		t.Fatalf("post-invoke = %q", got)
	}
	if _, ok := out["apt::default-release"]; ok {
		t.Fatalf("a plain value was read as a list")
	}
}

func TestRunInvokeHooks(t *testing.T) {
	dir := t.TempDir()
	old := cfg.Root
	defer func() { cfg.Root = old }()
	cfg.Root = dir
	os.MkdirAll(filepath.Join(dir, "etc/apt/apt.conf.d"), 0755)
	mark := filepath.Join(dir, "ran")
	os.WriteFile(filepath.Join(dir, "etc/apt/apt.conf.d/80test"), []byte(`DPkg::Pre-Invoke { "touch `+mark+`"; };`), 0644)
	if got := aptConfList("DPkg::Pre-Invoke"); len(got) != 1 {
		t.Fatalf("hooks = %q", got)
	}
	if err := runInvokeHooks("DPkg::Pre-Invoke"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(mark); err == nil {
		t.Fatalf("hooks ran for a foreign root")
	}
}
