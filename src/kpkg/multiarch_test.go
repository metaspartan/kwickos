package main

import (
	"archive/tar"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

func setupMA(t *testing.T, foreign ...string) {
	t.Helper()
	saved := cfg
	cfg = Config{Root: t.TempDir(), Arch: "amd64", Foreign: foreign, Avoid: map[string]bool{}}
	cfg.Admin = filepath.Join(cfg.Root, "var/lib/dpkg")
	t.Cleanup(func() { cfg = saved; curDB = nil })
}

func mkPkg(lines ...string) *Pkg {
	p := NewParagraph()
	for _, l := range lines {
		k, v, _ := strings.Cut(l, ": ")
		p.Set(k, v)
	}
	if p.Get("Architecture") == "" {
		p.Set("Architecture", "amd64")
	}
	if p.Get("Version") == "" {
		p.Set("Version", "1.0")
	}
	return newPkg(p)
}

func newTestDB(avail ...*Pkg) *DB {
	db := &DB{Avail: map[string][]*Pkg{}, Installed: map[string]*Installed{}, Auto: map[string]bool{}, provAvail: map[string][]provider{}}
	for _, p := range avail {
		db.addAvail(p)
	}
	for _, vs := range db.Avail {
		sort.SliceStable(vs, func(i, j int) bool { return CompareVersions(vs[i].Version, vs[j].Version) > 0 })
	}
	curDB = db
	return db
}

func (db *DB) markInstalled(p *Pkg) {
	db.Installed[p.InfoName()] = &Installed{Pkg: p, Status: "install ok installed"}
}

func resolveKeys(t *testing.T, db *DB, req ...string) (map[string]bool, error) {
	t.Helper()
	pl := db.NewPlan(ResolveOpts{Upgrade: true})
	for _, r := range req {
		p, err := resolveRequest(db, r)
		if err != nil {
			return nil, err
		}
		pl.Add(p, true)
	}
	if err := pl.Resolve(); err != nil {
		return nil, err
	}
	out := map[string]bool{}
	for k := range pl.Install {
		out[k] = true
	}
	return out, nil
}

func wantKeys(t *testing.T, got map[string]bool, want ...string) {
	t.Helper()
	var g []string
	for k := range got {
		g = append(g, k)
	}
	sort.Strings(g)
	sort.Strings(want)
	if strings.Join(g, " ") != strings.Join(want, " ") {
		t.Errorf("plan = %v, want %v", g, want)
	}
}

func TestParseDepsArchQualifiers(t *testing.T) {
	d := ParseDeps("a:any (>= 1), b:native, c:i386 | d, e", "amd64")
	if len(d) != 4 || d[0][0].Arch != "any" || d[0][0].Op != ">=" || d[1][0].Arch != "native" || d[2][0].Arch != "i386" || d[3][0].Arch != "" {
		t.Fatalf("bad parse: %v", d)
	}
	if got := d[0][0].String(); got != "a:any (>= 1)" {
		t.Errorf("String() = %q", got)
	}
}

func TestKeysAndInfoNames(t *testing.T) {
	setupMA(t, "i386")
	cases := []struct {
		arch, ma, key, info string
	}{
		{"amd64", "", "libc-bin", "libc-bin"},
		{"amd64", "same", "libc-bin", "libc-bin:amd64"},
		{"i386", "same", "libc-bin:i386", "libc-bin:i386"},
		{"i386", "foreign", "libc-bin:i386", "libc-bin:i386"},
		{"i386", "", "libc-bin:i386", "libc-bin:i386"},
		{"all", "", "libc-bin", "libc-bin"},
	}
	for _, c := range cases {
		p := mkPkg("Package: libc-bin", "Architecture: "+c.arch, "Multi-Arch: "+c.ma)
		if p.Key() != c.key || p.InfoName() != c.info {
			t.Errorf("%s/%s: key=%q info=%q, want %q %q", c.arch, c.ma, p.Key(), p.InfoName(), c.key, c.info)
		}
	}
}

func TestArchFits(t *testing.T) {
	setupMA(t, "i386")
	mk := func(arch, ma string) *Pkg { return mkPkg("Package: t", "Architecture: "+arch, "Multi-Arch: "+ma) }
	cases := []struct {
		q, from string
		t       *Pkg
		want    bool
		name    string
	}{
		{"", "amd64", mk("amd64", ""), true, "same arch"},
		{"", "i386", mk("amd64", ""), false, "no M-A is arch bound"},
		{"", "i386", mk("amd64", "same"), false, "same is arch bound"},
		{"", "i386", mk("amd64", "foreign"), true, "foreign satisfies any arch"},
		{"", "i386", mk("amd64", "allowed"), false, "allowed needs :any"},
		{"any", "i386", mk("amd64", "allowed"), true, "allowed with :any"},
		{"any", "i386", mk("amd64", "foreign"), true, "foreign with :any"},
		{"any", "i386", mk("amd64", ""), false, ":any needs M-A"},
		{"any", "amd64", mk("amd64", ""), true, ":any with same arch"},
		{"", "i386", mk("all", ""), true, "arch all satisfies any arch"},
		{"native", "i386", mk("amd64", ""), true, ":native"},
		{"native", "amd64", mk("i386", "foreign"), false, ":native rejects foreign arch"},
		{"i386", "amd64", mk("i386", ""), true, ":i386 explicit"},
		{"i386", "amd64", mk("amd64", "foreign"), false, ":i386 rejects amd64"},
		{"i386", "amd64", mk("all", ""), true, ":i386 accepts all"},
	}
	for _, c := range cases {
		if got := archFits(c.q, c.from, c.t); got != c.want {
			t.Errorf("%s: archFits(%q,%q,%s/%s)=%v want %v", c.name, c.q, c.from, c.t.Arch, c.t.MultiArch(), got, c.want)
		}
	}
}

func TestImplicitArchOfDependency(t *testing.T) {
	setupMA(t, "i386")
	db := newTestDB(
		mkPkg("Package: libc6", "Multi-Arch: same"),
		mkPkg("Package: libc6", "Architecture: i386", "Multi-Arch: same"),
		mkPkg("Package: app", "Depends: libc6"),
		mkPkg("Package: app32", "Architecture: i386", "Depends: libc6"),
	)
	got, err := resolveKeys(t, db, "app")
	if err != nil {
		t.Fatal(err)
	}
	wantKeys(t, got, "app", "libc6")
	got, err = resolveKeys(t, db, "app32:i386")
	if err != nil {
		t.Fatal(err)
	}
	wantKeys(t, got, "app32:i386", "libc6:i386")
}

func TestForeignDependencySatisfiedByNative(t *testing.T) {
	setupMA(t, "i386")
	db := newTestDB(
		mkPkg("Package: tool", "Multi-Arch: foreign"),
		mkPkg("Package: tool", "Architecture: i386", "Multi-Arch: foreign"),
		mkPkg("Package: lib32", "Architecture: i386", "Depends: tool"),
	)
	got, err := resolveKeys(t, db, "lib32:i386")
	if err != nil {
		t.Fatal(err)
	}
	wantKeys(t, got, "lib32:i386", "tool")
}

func TestNoMultiArchDependencyNotInstallable(t *testing.T) {
	setupMA(t, "i386")
	db := newTestDB(
		mkPkg("Package: tool"),
		mkPkg("Package: lib32", "Architecture: i386", "Depends: tool"),
	)
	if _, err := resolveKeys(t, db, "lib32:i386"); err == nil || !strings.Contains(err.Error(), "not installable") {
		t.Fatalf("expected unmet dependency, got %v", err)
	}
}

func TestInstalledNativeSatisfiesForeignDependency(t *testing.T) {
	setupMA(t, "i386")
	tool := mkPkg("Package: tool", "Multi-Arch: foreign")
	db := newTestDB(tool, mkPkg("Package: lib32", "Architecture: i386", "Depends: tool"))
	db.markInstalled(tool)
	got, err := resolveKeys(t, db, "lib32:i386")
	if err != nil {
		t.Fatal(err)
	}
	wantKeys(t, got, "lib32:i386")
}

func TestAnyQualifier(t *testing.T) {
	setupMA(t, "i386")
	db := newTestDB(
		mkPkg("Package: py", "Multi-Arch: allowed"),
		mkPkg("Package: mod", "Architecture: i386", "Depends: py:any"),
		mkPkg("Package: strict"),
		mkPkg("Package: mod2", "Architecture: i386", "Depends: strict:any"),
	)
	got, err := resolveKeys(t, db, "mod:i386")
	if err != nil {
		t.Fatal(err)
	}
	wantKeys(t, got, "mod:i386", "py")
	if _, err := resolveKeys(t, db, "mod2:i386"); err == nil {
		t.Fatal("pkg:any must not be satisfied by a package without Multi-Arch")
	}
}

func TestNativeQualifier(t *testing.T) {
	setupMA(t, "i386")
	db := newTestDB(
		mkPkg("Package: gen"),
		mkPkg("Package: gen", "Architecture: i386"),
		mkPkg("Package: user", "Architecture: i386", "Depends: gen:native"),
	)
	got, err := resolveKeys(t, db, "user:i386")
	if err != nil {
		t.Fatal(err)
	}
	wantKeys(t, got, "user:i386", "gen")
}

func TestExplicitArchQualifier(t *testing.T) {
	setupMA(t, "i386")
	db := newTestDB(
		mkPkg("Package: lib", "Multi-Arch: same"),
		mkPkg("Package: lib", "Architecture: i386", "Multi-Arch: same"),
		mkPkg("Package: user", "Depends: lib:i386"),
	)
	got, err := resolveKeys(t, db, "user")
	if err != nil {
		t.Fatal(err)
	}
	wantKeys(t, got, "user", "lib:i386")
}

func TestArchAllHandling(t *testing.T) {
	setupMA(t, "i386")
	db := newTestDB(
		mkPkg("Package: data", "Architecture: all"),
		mkPkg("Package: data", "Architecture: all"),
		mkPkg("Package: lib32", "Architecture: i386", "Depends: data"),
		mkPkg("Package: lib", "Multi-Arch: same"),
		mkPkg("Package: lib", "Architecture: i386", "Multi-Arch: same"),
		mkPkg("Package: needs-lib", "Architecture: all", "Depends: lib"),
	)
	if n := len(db.Avail["data"]); n != 1 {
		t.Errorf("arch all package listed %d times, want 1", n)
	}
	got, err := resolveKeys(t, db, "lib32:i386")
	if err != nil {
		t.Fatal(err)
	}
	wantKeys(t, got, "lib32:i386", "data")
	got, err = resolveKeys(t, db, "needs-lib")
	if err != nil {
		t.Fatal(err)
	}
	wantKeys(t, got, "needs-lib", "lib")
	got, err = resolveKeys(t, db, "data:i386")
	if err != nil {
		t.Fatal(err)
	}
	wantKeys(t, got, "data")
}

func TestVirtualProvidesRespectArch(t *testing.T) {
	setupMA(t, "i386")
	db := newTestDB(
		mkPkg("Package: impl", "Provides: virt"),
		mkPkg("Package: impl32", "Architecture: i386", "Provides: virt"),
		mkPkg("Package: user32", "Architecture: i386", "Depends: virt"),
	)
	got, err := resolveKeys(t, db, "user32:i386")
	if err != nil {
		t.Fatal(err)
	}
	wantKeys(t, got, "user32:i386", "impl32:i386")
}

func TestSameVersionLockstep(t *testing.T) {
	setupMA(t, "i386")
	old := mkPkg("Package: lib", "Version: 1.0", "Multi-Arch: same")
	db := newTestDB(
		old,
		mkPkg("Package: lib", "Version: 1.1", "Multi-Arch: same"),
		mkPkg("Package: lib", "Version: 1.1", "Architecture: i386", "Multi-Arch: same"),
	)
	db.markInstalled(old)
	got, err := resolveKeys(t, db, "lib:i386")
	if err != nil {
		t.Fatal(err)
	}
	wantKeys(t, got, "lib", "lib:i386")

	db2 := newTestDB(
		old,
		mkPkg("Package: lib", "Version: 1.1", "Architecture: i386", "Multi-Arch: same"),
	)
	db2.markInstalled(old)
	if _, err := resolveKeys(t, db2, "lib:i386"); err == nil || !strings.Contains(err.Error(), "versions differ") {
		t.Fatalf("expected version mismatch error, got %v", err)
	}
}

func TestConflictsApplyAcrossArchitectures(t *testing.T) {
	setupMA(t, "i386")
	victim := mkPkg("Package: old", "Architecture: i386")
	db := newTestDB(victim, mkPkg("Package: new", "Conflicts: old"))
	db.markInstalled(victim)
	pl := db.NewPlan(ResolveOpts{})
	p, _ := resolveRequest(db, "new")
	pl.Add(p, true)
	if err := pl.Resolve(); err != nil {
		t.Fatal(err)
	}
	if len(pl.Remove) != 1 || pl.Remove["old:i386"] == nil {
		t.Errorf("remove set = %v", pl.Remove)
	}
}

func TestSiblingInstancesDoNotConflict(t *testing.T) {
	setupMA(t, "i386")
	a := mkPkg("Package: lib", "Multi-Arch: same", "Breaks: lib (<< 0.5)")
	db := newTestDB(a, mkPkg("Package: lib", "Architecture: i386", "Multi-Arch: same", "Breaks: lib (<< 0.5)"))
	db.markInstalled(a)
	if _, err := resolveKeys(t, db, "lib:i386"); err != nil {
		t.Fatal(err)
	}
}

func TestOrderPutsForeignDependenciesFirst(t *testing.T) {
	setupMA(t, "i386")
	db := newTestDB(
		mkPkg("Package: libc6", "Architecture: i386", "Multi-Arch: same"),
		mkPkg("Package: libfoo", "Architecture: i386", "Multi-Arch: same", "Depends: libc6"),
		mkPkg("Package: top", "Architecture: i386", "Depends: libfoo"),
	)
	pl := db.NewPlan(ResolveOpts{})
	p, _ := resolveRequest(db, "top:i386")
	pl.Add(p, true)
	if err := pl.Resolve(); err != nil {
		t.Fatal(err)
	}
	var order []string
	for _, g := range pl.Order() {
		for _, x := range g {
			order = append(order, x.Key())
		}
	}
	if strings.Join(order, " ") != "libc6:i386 libfoo:i386 top:i386" {
		t.Errorf("order = %v", order)
	}
}

func TestResolveRequestQualifiers(t *testing.T) {
	setupMA(t, "i386")
	db := newTestDB(
		mkPkg("Package: lib", "Multi-Arch: same"),
		mkPkg("Package: lib", "Architecture: i386", "Multi-Arch: same"),
		mkPkg("Package: data", "Architecture: all"),
	)
	for req, want := range map[string]string{"lib": "lib", "lib:amd64": "lib", "lib:i386": "lib:i386", "lib:any": "lib", "data:i386": "data"} {
		p, err := resolveRequest(db, req)
		if err != nil || p.Key() != want {
			t.Errorf("%s -> %v %v, want %s", req, p, err, want)
		}
	}
	if _, err := resolveRequest(db, "lib:arm64"); err == nil || !strings.Contains(err.Error(), "not enabled") {
		t.Errorf("unconfigured arch error = %v", err)
	}
}

func TestLookupInstalledByArch(t *testing.T) {
	setupMA(t, "i386")
	a := mkPkg("Package: lib", "Multi-Arch: same")
	b := mkPkg("Package: lib", "Architecture: i386", "Multi-Arch: same")
	c := mkPkg("Package: solo", "Architecture: i386")
	d := mkPkg("Package: data", "Architecture: all")
	db := newTestDB()
	for _, p := range []*Pkg{a, b, c, d} {
		db.markInstalled(p)
	}
	check := func(name string, want *Pkg) {
		t.Helper()
		in := db.lookupInstalled(name)
		if want == nil {
			if in != nil {
				t.Errorf("%s: found %s", name, in.Key())
			}
			return
		}
		if in == nil || in.Pkg != want {
			t.Errorf("%s: wrong entry %v", name, in)
		}
	}
	check("lib", a)
	check("lib:amd64", a)
	check("lib:i386", b)
	check("solo", c)
	check("solo:i386", c)
	check("solo:amd64", nil)
	check("data", d)
	check("data:i386", d)
	check("data:any", d)
	check("lib:arm64", nil)
	if db.installedByKey("solo") != nil {
		t.Error("installedByKey must not return a foreign instance for the native key")
	}
}

func TestForeignArchitecturePersistence(t *testing.T) {
	setupMA(t)
	if err := addArchitecture("i386"); err != nil {
		t.Fatal(err)
	}
	if err := addArchitecture("i386"); err != nil {
		t.Fatal(err)
	}
	if err := addArchitecture("arm64"); err != nil {
		t.Fatal(err)
	}
	if err := addArchitecture("amd64"); err != nil {
		t.Fatal(err)
	}
	for _, bad := range []string{"all", "any", "", "I386", "x y"} {
		if err := addArchitecture(bad); err == nil {
			t.Errorf("addArchitecture(%q) should fail", bad)
		}
	}
	data, err := os.ReadFile(archFile())
	if err != nil || string(data) != "i386\narm64\n" {
		t.Fatalf("arch file = %q %v", data, err)
	}
	cfg.Foreign = nil
	if got := loadForeignArches(); strings.Join(got, ",") != "i386,arm64" {
		t.Errorf("reloaded %v", got)
	}
	cfg.Foreign = loadForeignArches()
	if err := removeArchitecture("arm64"); err != nil {
		t.Fatal(err)
	}
	if got := loadForeignArches(); strings.Join(got, ",") != "i386" {
		t.Errorf("after remove %v", got)
	}
}

func TestRemoveArchitectureInUse(t *testing.T) {
	setupMA(t, "i386")
	if err := saveForeignArches([]string{"i386"}); err != nil {
		t.Fatal(err)
	}
	st := "Package: lib\nStatus: install ok installed\nArchitecture: i386\nVersion: 1\n\n"
	if err := os.MkdirAll(cfg.Admin, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(statusPath(), []byte(st), 0644); err != nil {
		t.Fatal(err)
	}
	if err := removeArchitecture("i386"); err == nil || !strings.Contains(err.Error(), "in use") {
		t.Fatalf("expected in-use error, got %v", err)
	}
	if err := os.WriteFile(statusPath(), nil, 0644); err != nil {
		t.Fatal(err)
	}
	if err := removeArchitecture("i386"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(archFile()); !os.IsNotExist(err) {
		t.Error("arch file should be removed when no foreign architecture remains")
	}
}

func TestStatusKeyedByNameAndArch(t *testing.T) {
	setupMA(t, "i386")
	os.MkdirAll(cfg.Admin, 0755)
	st := "Package: lib\nStatus: install ok installed\nArchitecture: amd64\nMulti-Arch: same\nVersion: 1\n\n" +
		"Package: lib\nStatus: install ok installed\nArchitecture: i386\nMulti-Arch: same\nVersion: 1\n\n" +
		"Package: solo\nStatus: install ok installed\nArchitecture: i386\nVersion: 1\n\n" +
		"Package: native\nStatus: install ok installed\nArchitecture: amd64\nVersion: 1\n\n"
	os.WriteFile(statusPath(), []byte(st), 0644)
	db, err := OpenDB()
	if err != nil {
		t.Fatal(err)
	}
	var keys []string
	for k := range db.Installed {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	if strings.Join(keys, " ") != "lib:amd64 lib:i386 native solo:i386" {
		t.Errorf("status keys = %v", keys)
	}
}

func TestScriptIdentity(t *testing.T) {
	setupMA(t, "i386")
	a := mkPkg("Package: lib", "Multi-Arch: same")
	b := mkPkg("Package: lib", "Architecture: i386", "Multi-Arch: same")
	db := newTestDB()
	db.markInstalled(a)
	name, arch, ref := scriptIdentity("lib:amd64")
	if name != "lib" || arch != "amd64" || ref != 1 {
		t.Errorf("single instance: %s %s %d", name, arch, ref)
	}
	name, arch, ref = scriptIdentity("lib:i386")
	if name != "lib" || arch != "i386" || ref != 2 {
		t.Errorf("incoming second instance: %s %s %d", name, arch, ref)
	}
	db.markInstalled(b)
	if _, _, ref = scriptIdentity("lib:i386"); ref != 2 {
		t.Errorf("two instances: refcount %d", ref)
	}
	if _, arch, _ = scriptIdentity("data"); arch != "amd64" {
		t.Errorf("arch for unqualified name = %s", arch)
	}
	env := strings.Join(scriptEnv("lib:i386", "postinst"), "\n")
	for _, want := range []string{"DPKG_MAINTSCRIPT_ARCH=i386", "DPKG_MAINTSCRIPT_PACKAGE=lib\n", "DPKG_MAINTSCRIPT_PACKAGE_REFCOUNT=2"} {
		if !strings.Contains(env+"\n", want) {
			t.Errorf("script env lacks %q", want)
		}
	}
}

func TestSharedFilesMustBeIdentical(t *testing.T) {
	setupMA(t, "i386")
	dir := t.TempDir()
	f := filepath.Join(dir, "copyright")
	os.WriteFile(f, []byte("same text"), 0644)
	hdr := &tar.Header{Typeflag: tar.TypeReg, Name: "copyright", Size: 9}
	done, err := checkSharedIdentical(f, "/usr/share/doc/lib/copyright", hdr, strings.NewReader("same text"))
	if !done || err != nil {
		t.Errorf("identical file: done=%v err=%v", done, err)
	}
	if _, err := checkSharedIdentical(f, "/x", hdr, strings.NewReader("other txt")); err == nil {
		t.Error("differing file must be rejected")
	}
	if _, err := checkSharedIdentical(f, "/x", hdr, strings.NewReader("same text and more")); err == nil {
		t.Error("longer file must be rejected")
	}
	if done, err := checkSharedIdentical(filepath.Join(dir, "missing"), "/x", hdr, strings.NewReader("q")); done || err != nil {
		t.Errorf("missing file must be written: %v %v", done, err)
	}
	link := filepath.Join(dir, "lnk")
	os.Symlink("target", link)
	lh := &tar.Header{Typeflag: tar.TypeSymlink, Linkname: "target"}
	if done, err := checkSharedIdentical(link, "/l", lh, nil); !done || err != nil {
		t.Errorf("identical symlink: %v %v", done, err)
	}
	lh.Linkname = "elsewhere"
	if _, err := checkSharedIdentical(link, "/l", lh, nil); err == nil {
		t.Error("differing symlink must be rejected")
	}
}

func TestIndexLoadedForEveryArchitecture(t *testing.T) {
	setupMA(t, "i386")
	if got := strings.Join(allArches(), ","); got != "amd64,i386" {
		t.Fatalf("allArches = %s", got)
	}
	s := &Source{URI: "http://example.org/debian", Suite: "trixie", Comp: "main"}
	if !strings.HasSuffix(s.indexPath("i386"), "_main_binary-i386_Packages.kidx") {
		t.Errorf("index path %s", s.indexPath("i386"))
	}
	hashes := map[string]relEntry{"main/binary-i386/Packages.xz": {"abc", 3}}
	if name, _ := indexEntry(s, "i386", hashes); name != "main/binary-i386/Packages.xz" {
		t.Errorf("index entry %q", name)
	}
	if name, _ := indexEntry(s, "amd64", hashes); name != "" {
		t.Errorf("unexpected amd64 entry %q", name)
	}
}

func TestAutoInstalledMarksRoundTripPerArch(t *testing.T) {
	setupMA(t, "i386")
	db := newTestDB()
	db.markInstalled(mkPkg("Package: lib", "Multi-Arch: same"))
	db.markInstalled(mkPkg("Package: lib", "Architecture: i386", "Multi-Arch: same"))
	db.markInstalled(mkPkg("Package: data", "Architecture: all"))
	db.Auto["lib:i386"] = true
	db.Auto["data"] = true
	if err := db.SaveAuto(); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(extStatePath())
	if !strings.Contains(string(raw), "Package: lib\nArchitecture: i386\nAuto-Installed: 1") {
		t.Errorf("extended_states = %q", raw)
	}
	db2 := &DB{Auto: map[string]bool{}}
	db2.loadAuto()
	if !db2.Auto["lib:i386"] || db2.Auto["lib"] || !db2.Auto["data"] {
		t.Errorf("reloaded marks = %v", db2.Auto)
	}
}

func TestUpgradableUsesPerArchCandidates(t *testing.T) {
	setupMA(t, "i386")
	old32 := mkPkg("Package: lib", "Architecture: i386", "Version: 1", "Multi-Arch: same")
	db := newTestDB(old32,
		mkPkg("Package: lib", "Architecture: i386", "Version: 2", "Multi-Arch: same"),
		mkPkg("Package: lib", "Version: 1", "Multi-Arch: same"))
	db.provAvail = map[string][]provider{}
	db.markInstalled(old32)
	up := db.Upgradable()
	if len(up) != 1 || up[0].Key() != "lib:i386" || up[0].Version != "2" {
		t.Errorf("upgradable = %v", up)
	}
}

func TestAutoremoveKeepsForeignDependencies(t *testing.T) {
	setupMA(t, "i386")
	top := mkPkg("Package: top", "Architecture: i386", "Depends: lib")
	lib := mkPkg("Package: lib", "Architecture: i386", "Multi-Arch: same")
	libNative := mkPkg("Package: lib", "Multi-Arch: same")
	db := newTestDB()
	db.markInstalled(top)
	db.markInstalled(lib)
	db.markInstalled(libNative)
	db.Auto["lib:i386"] = true
	db.Auto["lib"] = true
	var gone []string
	for _, in := range db.Autoremovable() {
		gone = append(gone, in.Key())
	}
	if strings.Join(gone, " ") != "lib" {
		t.Errorf("autoremovable = %v, want only the native lib", gone)
	}
}
