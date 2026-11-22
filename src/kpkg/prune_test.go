package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPruneListsDropsRemovedSources(t *testing.T) {
	cfg.Lists = t.TempDir()
	keep := &Source{URI: "http://deb.debian.org/debian", Suite: "trixie", Comp: "main"}
	gone := &Source{URI: "http://127.0.0.1:8091", Suite: "stable", Comp: "main"}
	near := &Source{URI: "http://deb.debian.org/debian", Suite: "trixie-updates", Comp: "main"}
	files := []string{
		keep.base() + "_InRelease", keep.indexPath("riscv64"),
		gone.base() + "_InRelease", gone.indexPath("riscv64"),
		near.base() + "_InRelease", "lock",
	}
	for _, f := range files {
		if err := os.WriteFile(filepath.Join(cfg.Lists, filepath.Base(f)), []byte("x"), 0644); err != nil {
			t.Fatal(err)
		}
	}
	os.MkdirAll(filepath.Join(cfg.Lists, "partial"), 0755)
	pruneLists([]*Source{keep})
	exists := func(n string) bool { _, err := os.Stat(filepath.Join(cfg.Lists, filepath.Base(n))); return err == nil }
	for _, n := range []string{keep.base() + "_InRelease", keep.indexPath("riscv64"), "lock", "partial"} {
		if !exists(n) {
			t.Errorf("%s was removed", n)
		}
	}
	for _, n := range []string{gone.base() + "_InRelease", gone.indexPath("riscv64"), near.base() + "_InRelease"} {
		if exists(n) {
			t.Errorf("%s was kept", n)
		}
	}
}
