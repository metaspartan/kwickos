package main

import (
	"os"
	"path/filepath"
	"testing"
)

func buildModeDeb(t *testing.T, name string, modes map[string]os.FileMode) string {
	t.Helper()
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	os.MkdirAll(filepath.Join(src, "DEBIAN"), 0755)
	os.WriteFile(filepath.Join(src, "DEBIAN/control"), []byte("Package: "+name+"\nVersion: 1.0\nArchitecture: amd64\n"), 0644)
	for p, m := range modes {
		host := filepath.Join(src, p)
		os.MkdirAll(filepath.Dir(host), 0755)
		if err := os.WriteFile(host, []byte("x"), 0600); err != nil {
			t.Fatal(err)
		}
		if err := os.Chmod(host, m); err != nil {
			t.Fatal(err)
		}
	}
	out := filepath.Join(dir, name+".deb")
	if err := buildDeb(src, out); err != nil {
		t.Fatal(err)
	}
	return out
}

func TestExtractKeepsSetuidAndSetgid(t *testing.T) {
	setupMA(t)
	deb := buildModeDeb(t, "pamhelper", map[string]os.FileMode{
		"/usr/sbin/unix_chkpwd": 0755 | os.ModeSetgid,
		"/usr/bin/su-like":      0755 | os.ModeSetuid,
		"/usr/bin/plain":        0755,
	})
	want := map[string]os.FileMode{
		"usr/sbin/unix_chkpwd": 0755 | os.ModeSetgid,
		"usr/bin/su-like":      0755 | os.ModeSetuid,
		"usr/bin/plain":        0755,
	}
	check := func(stage string) {
		for p, m := range want {
			fi, err := os.Lstat(filepath.Join(cfg.Root, p))
			if err != nil {
				t.Fatalf("%s: %v", stage, err)
			}
			if got := fi.Mode() & (os.ModePerm | os.ModeSetuid | os.ModeSetgid); got != m {
				t.Errorf("%s: %s mode %v, want %v", stage, p, got, m)
			}
		}
	}
	if _, err := ExtractData(deb, nil, nil, nil, nil, nil); err != nil {
		t.Fatal(err)
	}
	check("fresh install")
	for p := range want {
		os.Chmod(filepath.Join(cfg.Root, p), 0644)
	}
	if _, err := ExtractData(deb, nil, nil, func(string) bool { return true }, nil, nil); err != nil {
		t.Fatal(err)
	}
	check("reinstall over stripped modes")
}
