package main

import (
	"crypto/md5"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func (db *DB) markHeld(p *Pkg) *Installed {
	p.P.Set("Status", "hold ok installed")
	in := &Installed{Pkg: p, Status: "hold ok installed"}
	db.Installed[p.InfoName()] = in
	return in
}

func TestHoldPinsCandidate(t *testing.T) {
	setupMA(t)
	old := mkPkg("Package: foo", "Version: 1.0")
	db := newTestDB(old, mkPkg("Package: foo", "Version: 2.0"))
	in := db.markHeld(mkPkg("Package: foo", "Version: 1.0"))
	if v := candVersion(db, "foo"); v != "1.0" {
		t.Fatalf("held candidate = %s, want 1.0", v)
	}
	if got := strings.Join(db.heldBack(), ","); got != "foo" {
		t.Errorf("heldBack = %q", got)
	}
	if len(db.Upgradable()) != 0 {
		t.Errorf("held package listed as upgradable")
	}
	in.Status = "install ok installed"
	db.cand = nil
	if v := candVersion(db, "foo"); v != "2.0" {
		t.Errorf("unheld candidate = %s, want 2.0", v)
	}
	in.Status = "hold ok installed"
	db.cand = nil
	cfg.AllowHeld = true
	if v := candVersion(db, "foo"); v != "2.0" {
		t.Errorf("--allow-change-held-packages candidate = %s, want 2.0", v)
	}
}

func TestHoldBlocksDependencyUpgrade(t *testing.T) {
	setupMA(t)
	db := newTestDB(
		mkPkg("Package: foo", "Version: 1.0"),
		mkPkg("Package: foo", "Version: 2.0"),
		mkPkg("Package: bar", "Version: 1.0", "Depends: foo (>= 2.0)"),
	)
	db.markHeld(mkPkg("Package: foo", "Version: 1.0"))
	pl := db.NewPlan(ResolveOpts{Upgrade: true})
	pl.Add(db.Candidate("bar"), true)
	if err := pl.Resolve(); err == nil {
		t.Fatalf("held foo was upgraded: %v", sortedKeys(pl.Install))
	}
	cfg.AllowHeld = true
	db.cand = nil
	pl = db.NewPlan(ResolveOpts{Upgrade: true})
	pl.Add(db.Candidate("bar"), true)
	if err := pl.Resolve(); err != nil {
		t.Fatal(err)
	}
	if p := pl.Install["foo"]; p == nil || p.Version != "2.0" {
		t.Errorf("foo not upgraded with --allow-change-held-packages")
	}
}

func TestHoldBlocksRemoval(t *testing.T) {
	setupMA(t)
	db := newTestDB()
	db.markHeld(mkPkg("Package: foo"))
	if _, err := db.RemovalPlan([]string{"foo"}); err == nil {
		t.Fatal("held package removal allowed")
	}
}

func TestSetStateKeepsHold(t *testing.T) {
	setupMA(t)
	db := newTestDB()
	in := db.markHeld(mkPkg("Package: foo"))
	in.setState("install", "half-configured")
	if in.Status != "hold ok half-configured" || in.P.Get("Status") != in.Status {
		t.Errorf("status = %q / %q", in.Status, in.P.Get("Status"))
	}
}

func TestSetSelectionsRoundTrip(t *testing.T) {
	setupMA(t)
	db := newTestDB()
	p := mkPkg("Package: foo", "Status: install ok installed")
	db.Installed[p.InfoName()] = &Installed{Pkg: p, Status: "install ok installed"}
	if err := db.SaveStatus(); err != nil {
		t.Fatal(err)
	}
	if err := setSelections(db, map[string]string{"foo": "hold"}, false); err != nil {
		t.Fatal(err)
	}
	re, err := OpenDB()
	if err != nil {
		t.Fatal(err)
	}
	if in := re.lookupInstalled("foo"); in == nil || !in.Held() {
		t.Fatalf("hold not persisted: %+v", in)
	}
	if err := setSelections(re, map[string]string{"foo": "install"}, false); err != nil {
		t.Fatal(err)
	}
	re, _ = OpenDB()
	if in := re.lookupInstalled("foo"); in == nil || in.Status != "install ok installed" {
		t.Fatalf("unhold not persisted: %+v", in)
	}
}

func TestAutoremoveIgnoresResidualConfig(t *testing.T) {
	setupMA(t)
	db := newTestDB()
	gone := mkPkg("Package: nginx", "Depends: libfoo")
	db.Installed[gone.InfoName()] = &Installed{Pkg: gone, Status: "deinstall ok config-files"}
	db.markInstalled(mkPkg("Package: libfoo"))
	db.Auto["libfoo"] = true
	var names []string
	for _, in := range db.Autoremovable() {
		names = append(names, in.Key())
	}
	if strings.Join(names, ",") != "libfoo" {
		t.Errorf("autoremovable = %v, want [libfoo]", names)
	}
}

func md5hex(s string) string {
	h := md5.Sum([]byte(s))
	return hex.EncodeToString(h[:])
}

func buildConfDeb(t *testing.T, dir, version, content string) string {
	t.Helper()
	src := filepath.Join(dir, "src-"+version)
	os.MkdirAll(filepath.Join(src, "DEBIAN"), 0755)
	os.MkdirAll(filepath.Join(src, "etc"), 0755)
	os.WriteFile(filepath.Join(src, "DEBIAN/control"), []byte("Package: foo\nVersion: "+version+"\nArchitecture: amd64\n"), 0644)
	os.WriteFile(filepath.Join(src, "DEBIAN/conffiles"), []byte("/etc/foo.conf\n"), 0644)
	os.WriteFile(filepath.Join(src, "etc/foo.conf"), []byte(content), 0644)
	out := filepath.Join(dir, "foo_"+version+".deb")
	if err := buildDeb(src, out); err != nil {
		t.Fatal(err)
	}
	return out
}

func TestConffileUpgradeSemantics(t *testing.T) {
	setupMA(t)
	work := t.TempDir()
	conf := map[string]bool{"/etc/foo.conf": true}
	host := filepath.Join(cfg.Root, "etc/foo.conf")
	os.MkdirAll(filepath.Dir(host), 0755)

	os.WriteFile(host, []byte("local\n"), 0644)
	deb := buildConfDeb(t, work, "1.1", "shipped\n")
	if _, err := ExtractData(deb, conf, map[string]string{"/etc/foo.conf": md5hex("shipped\n")}, nil, nil); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(host); string(b) != "local\n" {
		t.Errorf("local edit lost: %q", b)
	}
	if _, err := os.Stat(host + ".dpkg-dist"); err == nil {
		t.Errorf("spurious .dpkg-dist for an unchanged conffile")
	}

	deb2 := buildConfDeb(t, work, "2.0", "shipped v2\n")
	if _, err := ExtractData(deb2, conf, map[string]string{"/etc/foo.conf": md5hex("shipped\n")}, nil, nil); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(host + ".dpkg-dist"); string(b) != "shipped v2\n" {
		t.Errorf("new conffile not saved as .dpkg-dist: %q", b)
	}

	os.Remove(host)
	os.Remove(host + ".dpkg-dist")
	if _, err := ExtractData(deb2, conf, map[string]string{"/etc/foo.conf": md5hex("shipped\n")}, nil, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(host); err == nil {
		t.Errorf("conffile deleted by the admin was re-created")
	}

	if _, err := ExtractData(deb2, conf, nil, nil, nil); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(host); string(b) != "shipped v2\n" {
		t.Errorf("fresh install did not create conffile: %q", b)
	}

	os.WriteFile(host, []byte("shipped\n"), 0644)
	if _, err := ExtractData(deb2, conf, map[string]string{"/etc/foo.conf": md5hex("shipped\n")}, nil, nil); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(host); string(b) != "shipped v2\n" {
		t.Errorf("unmodified conffile not upgraded: %q", b)
	}
}
