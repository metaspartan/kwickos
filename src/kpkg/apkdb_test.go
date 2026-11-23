package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func buildTestDeb(t *testing.T, name string, files map[string]string, extra int) string {
	t.Helper()
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	os.MkdirAll(filepath.Join(src, "DEBIAN"), 0755)
	os.WriteFile(filepath.Join(src, "DEBIAN/control"), []byte("Package: "+name+"\nVersion: 1.0\nArchitecture: amd64\n"), 0644)
	for i := 0; i < extra; i++ {
		files[fmt.Sprintf("/usr/share/%s/f%d", name, i)] = fmt.Sprintf("data %d", i)
	}
	for p, c := range files {
		host := filepath.Join(src, p)
		os.MkdirAll(filepath.Dir(host), 0755)
		if tgt, ok := strings.CutPrefix(c, "->"); ok {
			os.Symlink(tgt, host)
			continue
		}
		os.WriteFile(host, []byte(c), 0644)
	}
	out := filepath.Join(dir, name+".deb")
	if err := buildDeb(src, out); err != nil {
		t.Fatal(err)
	}
	return out
}

const apkDB = `C:Q1AAAAAAAAAAAAAAAAAAAAAAAAAAA=
P:kwick-base
V:0.7.0-r0
A:x86_64
o:kwick-base
p:busybox=1.38.0-r0 /bin/sh cmd:sh
F:usr/bin
R:busybox
R:basefile

C:Q1BBBBBBBBBBBBBBBBBBBBBBBBBBB=
P:jq
V:1.7.1-r0
A:x86_64
o:jq
F:usr
F:usr/bin
R:jq
a:0:0:755
Z:Q1abc=
F:bin
R:oldtool

`

func apkRoot(t *testing.T, usrMerged bool) {
	t.Helper()
	setupMA(t)
	os.MkdirAll(filepath.Join(cfg.Root, "usr/lib/apk/db"), 0755)
	os.WriteFile(filepath.Join(cfg.Root, "usr/lib/apk/db/installed"), []byte(apkDB), 0644)
	if usrMerged {
		os.MkdirAll(filepath.Join(cfg.Root, "usr/bin"), 0755)
		os.Symlink("usr/bin", filepath.Join(cfg.Root, "bin"))
		os.Symlink("usr/lib", filepath.Join(cfg.Root, "lib"))
	}
}

func testTx() *Tx {
	db := newTestDB()
	return &Tx{db: db, plan: db.NewPlan(ResolveOpts{}), activated: map[string]bool{}, prevVer: map[string]string{}}
}

func TestParseApkInstalled(t *testing.T) {
	var got []string
	parseApkInstalled(apkDB, func(pkg, dir, name string) { got = append(got, pkg+":"+dir+"/"+name) })
	if strings.Join(got, " ") != "jq:usr/bin/jq jq:bin/oldtool" {
		t.Fatalf("apk entries %v", got)
	}
}

func TestDebRefusesApkOwnedFile(t *testing.T) {
	apkRoot(t, true)
	deb := buildTestDeb(t, "jq", map[string]string{"/usr/bin/jq": "debian jq"}, 0)
	p := &Pkg{Name: "jq", Version: "1.7.1-1"}
	err := testTx().checkApkConflicts(p, deb)
	if err == nil || !strings.Contains(err.Error(), "'/usr/bin/jq', which is also in Alpine (apk) package jq") || !strings.Contains(err.Error(), "apk del jq") {
		t.Fatalf("conflict not reported: %v", err)
	}
	cfg.ForceOverwrite = true
	if err := testTx().checkApkConflicts(p, deb); err != nil {
		t.Fatalf("--force-overwrite: %v", err)
	}
}

func TestApkConflictFollowsUsrMerge(t *testing.T) {
	apkRoot(t, true)
	deb := buildTestDeb(t, "oldtool", map[string]string{"/usr/bin/oldtool": "x"}, 0)
	if err := testTx().checkApkConflicts(&Pkg{Name: "oldtool"}, deb); err == nil {
		t.Fatal("/bin/oldtool from apk not matched through the /bin -> usr/bin link")
	}
}

func TestApkKwickBaseEntriesIgnored(t *testing.T) {
	apkRoot(t, true)
	deb := buildTestDeb(t, "busybox", map[string]string{"/usr/bin/busybox": "x", "/usr/bin/basefile": "y", "/usr/bin/jq2": "z"}, 3)
	if err := testTx().checkApkConflicts(&Pkg{Name: "busybox"}, deb); err != nil {
		t.Fatalf("kwick-base's virtual apk entry blocked a Debian package: %v", err)
	}
}

func TestApkConflictSkipsExcludedPaths(t *testing.T) {
	apkRoot(t, true)
	cfg.PathFilters = []filterRule{{pat: "/usr/bin/jq"}}
	deb := buildTestDeb(t, "jq", map[string]string{"/usr/bin/jq": "x"}, 0)
	if err := testTx().checkApkConflicts(&Pkg{Name: "jq"}, deb); err != nil {
		t.Fatalf("path-excluded file reported as conflict: %v", err)
	}
}

func TestNoApkDatabaseNoCost(t *testing.T) {
	setupMA(t)
	tx := testTx()
	if err := tx.checkApkConflicts(&Pkg{Name: "x"}, "/nonexistent.deb"); err != nil {
		t.Fatal(err)
	}
	if len(tx.apkOwners) != 0 {
		t.Fatal("phantom apk owners")
	}
}

func TestUnpackRefusesApkConflictBeforeTouchingFiles(t *testing.T) {
	apkRoot(t, true)
	os.WriteFile(filepath.Join(cfg.Root, "usr/bin/jq"), []byte("alpine jq"), 0755)
	deb := buildTestDeb(t, "jq", map[string]string{"/usr/bin/jq": "debian jq"}, 0)
	tx := testTx()
	err := tx.unpack(&Pkg{Name: "jq", Version: "1.0", Arch: "amd64"}, deb)
	if err == nil {
		t.Fatal("unpack overwrote an apk-owned file")
	}
	if b, _ := os.ReadFile(filepath.Join(cfg.Root, "usr/bin/jq")); string(b) != "alpine jq" {
		t.Fatalf("apk file clobbered: %q", b)
	}
	if tx.db.Installed["jq"] != nil {
		t.Fatal("refused package recorded as installed")
	}
}
