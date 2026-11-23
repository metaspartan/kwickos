package main

import (
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const trixieRelease = "Origin: Debian\nLabel: Debian\nSuite: stable\nCodename: trixie\nVersion: 13.7\n"
const bpoRelease = "Origin: Debian Backports\nLabel: Debian Backports\nSuite: stable-backports\nCodename: trixie-backports\nNotAutomatic: yes\nButAutomaticUpgrades: yes\n"
const expRelease = "Origin: Debian\nLabel: Debian\nSuite: experimental\nCodename: rc-buggy\nNotAutomatic: yes\n"

type pinEnv struct {
	trixie, bpo, exp *Source
}

func setupPins(t *testing.T) *pinEnv {
	t.Helper()
	setupMA(t)
	cfg.Lists = filepath.Join(cfg.Root, "var/lib/apt/lists")
	os.MkdirAll(cfg.Lists, 0755)
	mk := func(uri, suite, rel string) *Source {
		s := &Source{URI: uri, Suite: suite, Comp: "main"}
		if rel != "" {
			os.WriteFile(filepath.Join(cfg.Lists, s.base()+"_InRelease"), []byte("-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA256\n\n"+rel+"\n-----BEGIN PGP SIGNATURE-----\nx\n-----END PGP SIGNATURE-----\n"), 0644)
		}
		return s
	}
	return &pinEnv{
		trixie: mk("http://deb.debian.org/debian", "trixie", trixieRelease),
		bpo:    mk("http://deb.debian.org/debian", "trixie-backports", bpoRelease),
		exp:    mk("http://deb.debian.org/debian", "experimental", expRelease),
	}
}

func writePrefs(t *testing.T, name, body string) {
	t.Helper()
	dir := filepath.Join(cfg.Root, "etc/apt/preferences.d")
	os.MkdirAll(dir, 0755)
	if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0644); err != nil {
		t.Fatal(err)
	}
}

func from(s *Source, lines ...string) *Pkg {
	p := mkPkg(lines...)
	p.Src = s
	return p
}

func candVersion(db *DB, name string) string {
	if c := db.Candidate(name); c != nil {
		return c.Version
	}
	return ""
}

func TestDefaultPriorities(t *testing.T) {
	e := setupPins(t)
	db := newTestDB(
		from(e.trixie, "Package: samba", "Version: 4.22"),
		from(e.bpo, "Package: samba", "Version: 4.24~bpo13+1"),
		from(e.exp, "Package: samba", "Version: 4.99"),
		from(e.bpo, "Package: only-bpo", "Version: 2.0~bpo13+1"),
	)
	pl := db.policy()
	if p := pl.filePrio(e.trixie, "amd64"); p != 500 {
		t.Errorf("trixie=%d", p)
	}
	if p := pl.filePrio(e.bpo, "amd64"); p != 100 {
		t.Errorf("backports=%d", p)
	}
	if p := pl.filePrio(e.exp, "amd64"); p != 1 {
		t.Errorf("experimental=%d", p)
	}
	if v := candVersion(db, "samba"); v != "4.22" {
		t.Errorf("samba candidate %q", v)
	}
	if v := candVersion(db, "only-bpo"); v != "2.0~bpo13+1" {
		t.Errorf("only-bpo candidate %q", v)
	}
}

func TestInstalledBackportsUpgrade(t *testing.T) {
	e := setupPins(t)
	old := from(e.bpo, "Package: zfsutils-linux", "Version: 2.3~bpo13+1")
	db := newTestDB(
		old,
		from(e.bpo, "Package: zfsutils-linux", "Version: 2.4~bpo13+1"),
		from(e.trixie, "Package: zfsutils-linux", "Version: 2.2"),
	)
	inst := mkPkg("Package: zfsutils-linux", "Version: 2.3~bpo13+1")
	db.markInstalled(inst)
	if v := candVersion(db, "zfsutils-linux"); v != "2.4~bpo13+1" {
		t.Errorf("installed backports package should follow backports, got %q", v)
	}
	db2 := newTestDB(
		from(e.bpo, "Package: curl", "Version: 8.2~bpo13+1"),
		from(e.trixie, "Package: curl", "Version: 8.1"),
	)
	db2.markInstalled(mkPkg("Package: curl", "Version: 8.1"))
	if v := candVersion(db2, "curl"); v != "8.1" {
		t.Errorf("installed trixie package must not move to backports, got %q", v)
	}
	if len(db2.Upgradable()) != 0 {
		t.Errorf("unexpected upgrades %v", db2.Upgradable())
	}
}

func TestPinTable(t *testing.T) {
	cases := []struct {
		name, prefs, pkg, want string
	}{
		{"none", "", "samba", "4.22"},
		{"release a= suite", "Package: samba\nPin: release a=stable-backports\nPin-Priority: 600\n", "samba", "4.24~bpo13+1"},
		{"release n= codename", "Package: samba\nPin: release n=trixie-backports\nPin-Priority: 600\n", "samba", "4.24~bpo13+1"},
		{"release a= codename does not match", "Package: samba\nPin: release a=trixie-backports\nPin-Priority: 600\n", "samba", "4.22"},
		{"release o=", "Package: samba\nPin: release o=Debian Backports\nPin-Priority: 600\n", "samba", "4.24~bpo13+1"},
		{"release l=", "Package: samba\nPin: release l=Debian Backports\nPin-Priority: 600\n", "samba", "4.24~bpo13+1"},
		{"release c= and a=", "Package: samba\nPin: release a=stable-backports,c=main\nPin-Priority: 600\n", "samba", "4.24~bpo13+1"},
		{"release compound mismatch", "Package: samba\nPin: release a=stable-backports,c=contrib\nPin-Priority: 600\n", "samba", "4.22"},
		{"release v=", "Package: samba\nPin: release v=13*\nPin-Priority: 600\n", "samba", "4.22"},
		{"release case-insensitive", "Package: samba\nPin: release A=STABLE-BACKPORTS\nPin-Priority: 600\n", "samba", "4.24~bpo13+1"},
		{"bare release", "Package: samba\nPin: release trixie-backports\nPin-Priority: 600\n", "samba", "4.24~bpo13+1"},
		{"release b=", "Package: samba\nPin: release b=amd64,n=trixie-backports\nPin-Priority: 600\n", "samba", "4.24~bpo13+1"},
		{"origin host", "Package: samba\nPin: origin deb.debian.org\nPin-Priority: 600\n", "samba", "4.24~bpo13+1"},
		{"origin other host", "Package: samba\nPin: origin example.org\nPin-Priority: 600\n", "samba", "4.22"},
		{"origin empty", "Package: samba\nPin: origin \"\"\nPin-Priority: 600\n", "samba", "4.22"},
		{"version exact", "Package: samba\nPin: version 4.24~bpo13+1\nPin-Priority: 600\n", "samba", "4.24~bpo13+1"},
		{"version glob", "Package: samba\nPin: version 4.24*\nPin-Priority: 600\n", "samba", "4.24~bpo13+1"},
		{"version glob nomatch", "Package: samba\nPin: version 5.*\nPin-Priority: 600\n", "samba", "4.22"},
		{"negative blocks", "Package: samba\nPin: version 4.22\nPin-Priority: -1\n", "samba", "4.24~bpo13+1"},
		{"negative blocks backports", "Package: samba\nPin: release a=stable-backports\nPin-Priority: -1\n", "samba", "4.22"},
		{"glob package", "Package: sam*\nPin: release n=trixie-backports\nPin-Priority: 600\n", "samba", "4.24~bpo13+1"},
		{"glob package nomatch", "Package: smb*\nPin: release n=trixie-backports\nPin-Priority: 600\n", "samba", "4.22"},
		{"regex package", "Package: /^sa.b/\nPin: release n=trixie-backports\nPin-Priority: 600\n", "samba", "4.24~bpo13+1"},
		{"package list", "Package: curl samba\nPin: release n=trixie-backports\nPin-Priority: 600\n", "samba", "4.24~bpo13+1"},
		{"star release", "Package: *\nPin: release n=trixie-backports\nPin-Priority: 600\n", "samba", "4.24~bpo13+1"},
		{"star version ignored", "Package: *\nPin: version 4.24*\nPin-Priority: 900\n", "samba", "4.22"},
		{"first named stanza wins", "Package: samba\nPin: release n=trixie\nPin-Priority: 200\n\nPackage: samba\nPin: release n=trixie-backports\nPin-Priority: 300\n", "samba", "4.24~bpo13+1"},
		{"glob before exact wins", "Package: sam*\nPin: release n=trixie-backports\nPin-Priority: 700\n\nPackage: samba\nPin: release n=trixie-backports\nPin-Priority: 50\n", "samba", "4.24~bpo13+1"},
		{"named beats star", "Package: *\nPin: release n=trixie-backports\nPin-Priority: 900\n\nPackage: samba\nPin: release n=trixie-backports\nPin-Priority: 50\n", "samba", "4.22"},
		{"release then version first wins", "Package: samba\nPin: release n=trixie\nPin-Priority: 50\n\nPackage: samba\nPin: version 4.22\nPin-Priority: 700\n", "samba", "4.24~bpo13+1"},
		{"comments and explanation", "# note\nExplanation: x\nPackage: samba\nPin: release n=trixie-backports\nPin-Priority: 600\n", "samba", "4.24~bpo13+1"},
		{"zero priority ignored", "Package: samba\nPin: release n=trixie-backports\nPin-Priority: 0\n", "samba", "4.22"},
		{"unknown pin type ignored", "Package: samba\nPin: foo bar\nPin-Priority: 900\n", "samba", "4.22"},
		{"pin at 500 reaches backports on tie", "Package: samba\nPin: release n=trixie-backports\nPin-Priority: 500\n", "samba", "4.24~bpo13+1"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			e := setupPins(t)
			if c.prefs != "" {
				writePrefs(t, "t", c.prefs)
			}
			db := newTestDB(
				from(e.trixie, "Package: samba", "Version: 4.22"),
				from(e.bpo, "Package: samba", "Version: 4.24~bpo13+1"),
			)
			if got := candVersion(db, c.pkg); got != c.want {
				t.Errorf("candidate %q want %q", got, c.want)
			}
		})
	}
}

func TestPreferencesFiles(t *testing.T) {
	e := setupPins(t)
	os.MkdirAll(filepath.Join(cfg.Root, "etc/apt"), 0755)
	os.WriteFile(filepath.Join(cfg.Root, "etc/apt/preferences"), []byte("Package: samba\nPin: release n=trixie-backports\nPin-Priority: 600\n"), 0644)
	writePrefs(t, "10-a.pref", "Package: curl\nPin: release n=trixie-backports\nPin-Priority: 600\n")
	writePrefs(t, "20-b.disabled", "Package: bash\nPin: release n=trixie-backports\nPin-Priority: 600\n")
	writePrefs(t, "30-c", "Package: zsh\nPin: release n=trixie-backports\nPin-Priority: 600\n")
	var avail []*Pkg
	for _, n := range []string{"samba", "curl", "bash", "zsh"} {
		avail = append(avail, from(e.trixie, "Package: "+n, "Version: 1"), from(e.bpo, "Package: "+n, "Version: 2~bpo13+1"))
	}
	db := newTestDB(avail...)
	got := map[string]string{}
	for _, n := range []string{"samba", "curl", "bash", "zsh"} {
		got[n] = candVersion(db, n)
	}
	want := map[string]string{"samba": "2~bpo13+1", "curl": "2~bpo13+1", "bash": "1", "zsh": "2~bpo13+1"}
	for n, v := range want {
		if got[n] != v {
			t.Errorf("%s: got %q want %q", n, got[n], v)
		}
	}
}

func TestDefaultRelease(t *testing.T) {
	e := setupPins(t)
	mk := func() *DB {
		return newTestDB(
			from(e.trixie, "Package: samba", "Version: 4.22"),
			from(e.bpo, "Package: samba", "Version: 4.24~bpo13+1"),
			from(e.bpo, "Package: only-bpo", "Version: 1~bpo13+1"),
		)
	}
	db := mk()
	if v := candVersion(db, "samba"); v != "4.22" {
		t.Errorf("default %q", v)
	}
	cfg.TargetRelease = "trixie-backports"
	db = mk()
	if p := db.policy().filePrio(e.bpo, "amd64"); p != 990 {
		t.Errorf("target release priority %d", p)
	}
	if v := candVersion(db, "samba"); v != "4.24~bpo13+1" {
		t.Errorf("-t trixie-backports gave %q", v)
	}
	cfg.TargetRelease = "stable"
	db = mk()
	if v := candVersion(db, "samba"); v != "4.22" {
		t.Errorf("-t stable gave %q", v)
	}
	if v := candVersion(db, "only-bpo"); v != "1~bpo13+1" {
		t.Errorf("only-bpo gave %q", v)
	}
	cfg.TargetRelease = "13.7"
	db = mk()
	if p := db.policy().filePrio(e.trixie, "amd64"); p != 990 {
		t.Errorf("-t by version priority %d", p)
	}
	cfg.TargetRelease = ""
	os.MkdirAll(filepath.Join(cfg.Root, "etc/apt/apt.conf.d"), 0755)
	os.WriteFile(filepath.Join(cfg.Root, "etc/apt/apt.conf.d/99dr"), []byte("// c\nAPT::Default-Release \"trixie-backports\";\n"), 0644)
	db = mk()
	if v := candVersion(db, "samba"); v != "4.24~bpo13+1" {
		t.Errorf("apt.conf Default-Release gave %q", v)
	}
	os.WriteFile(filepath.Join(cfg.Root, "etc/apt/apt.conf.d/99dr"), []byte("APT {\n  Default-Release \"trixie-backports\";\n};\n"), 0644)
	db = mk()
	if v := candVersion(db, "samba"); v != "4.24~bpo13+1" {
		t.Errorf("nested apt.conf Default-Release gave %q", v)
	}
}

func TestPinPrecedence(t *testing.T) {
	e := setupPins(t)
	cfg.TargetRelease = "trixie"
	writePrefs(t, "t", "Package: *\nPin: release n=trixie\nPin-Priority: 300\n")
	db := newTestDB(from(e.trixie, "Package: a", "Version: 1"))
	if p := db.Prio(db.Avail["a"][0]); p != 990 {
		t.Errorf("default release should beat star pin, got %d", p)
	}
	writePrefs(t, "t", "Package: a\nPin: version 1\nPin-Priority: 300\n")
	db = newTestDB(from(e.trixie, "Package: a", "Version: 1"))
	if p := db.Prio(db.Avail["a"][0]); p != 300 {
		t.Errorf("named pin should beat default release, got %d", p)
	}
}

func TestDowngradeNeedsPriorityOver1000(t *testing.T) {
	e := setupPins(t)
	avail := func() []*Pkg {
		return []*Pkg{
			from(e.trixie, "Package: pkg", "Version: 2"),
			from(e.trixie, "Package: pkg", "Version: 1"),
		}
	}
	writePrefs(t, "t", "Package: pkg\nPin: version 1\nPin-Priority: 900\n")
	db := newTestDB(avail()...)
	db.markInstalled(mkPkg("Package: pkg", "Version: 2"))
	if v := candVersion(db, "pkg"); v != "2" {
		t.Errorf("pin below 1000 must not downgrade, got %q", v)
	}
	writePrefs(t, "t", "Package: pkg\nPin: version 1\nPin-Priority: 1001\n")
	db = newTestDB(avail()...)
	db.markInstalled(mkPkg("Package: pkg", "Version: 2"))
	if v := candVersion(db, "pkg"); v != "1" {
		t.Errorf("pin above 1000 must downgrade, got %q", v)
	}
	if up := db.Upgradable(); len(up) != 1 || up[0].Version != "1" {
		t.Errorf("downgrade should be offered: %v", up)
	}
}

func TestInstalledOnlyNewerThanArchive(t *testing.T) {
	e := setupPins(t)
	db := newTestDB(from(e.trixie, "Package: pkg", "Version: 1"))
	db.markInstalled(mkPkg("Package: pkg", "Version: 3"))
	if c := db.Candidate("pkg"); c != nil {
		t.Errorf("older archive version must not become a candidate, got %s", c.Version)
	}
	p, err := resolveRequest(db, "pkg")
	if err != nil || p.Version != "3" {
		t.Errorf("resolveRequest = %v %v", p, err)
	}
}

func TestBlockedPackageHasNoCandidate(t *testing.T) {
	e := setupPins(t)
	writePrefs(t, "t", "Package: pkg\nPin: release n=trixie\nPin-Priority: -1\n")
	db := newTestDB(from(e.trixie, "Package: pkg", "Version: 1"))
	if _, err := resolveRequest(db, "pkg"); err == nil || !strings.Contains(err.Error(), "no installation candidate") {
		t.Errorf("err=%v", err)
	}
}

func TestExplicitVersionAndSuiteRequests(t *testing.T) {
	e := setupPins(t)
	db := newTestDB(
		from(e.trixie, "Package: samba", "Version: 4.22"),
		from(e.bpo, "Package: samba", "Version: 4.24~bpo13+1"),
	)
	if p, _ := resolveRequest(db, "samba"); p.Version != "4.22" {
		t.Errorf("plain request got %s", p.Version)
	}
	if p, _ := resolveRequest(db, "samba/trixie-backports"); p.Version != "4.24~bpo13+1" {
		t.Errorf("/suite request got %s", p.Version)
	}
	if p, _ := resolveRequest(db, "samba/stable-backports"); p.Version != "4.24~bpo13+1" {
		t.Errorf("/archive request got %s", p.Version)
	}
	if p, _ := resolveRequest(db, "samba=4.24~bpo13+1"); p.Version != "4.24~bpo13+1" {
		t.Errorf("=version request got %s", p.Version)
	}
}

func TestDependenciesPreferTrixie(t *testing.T) {
	e := setupPins(t)
	db := newTestDB(
		from(e.trixie, "Package: samba", "Version: 4.22", "Depends: libwb (>= 4.0), libldb | libldb-alt"),
		from(e.bpo, "Package: samba", "Version: 4.24~bpo13+1", "Depends: libwb (>= 4.0)"),
		from(e.trixie, "Package: libwb", "Version: 4.22"),
		from(e.bpo, "Package: libwb", "Version: 4.24~bpo13+1"),
		from(e.trixie, "Package: libldb", "Version: 2.0"),
		from(e.bpo, "Package: libldb", "Version: 2.1~bpo13+1"),
	)
	got, err := resolveKeys(t, db, "samba")
	if err != nil {
		t.Fatal(err)
	}
	for _, k := range []string{"samba", "libwb", "libldb"} {
		if !got[k] {
			t.Errorf("%s not planned: %v", k, got)
		}
	}
	pl := db.NewPlan(ResolveOpts{Upgrade: true})
	p, _ := resolveRequest(db, "samba")
	pl.Add(p, true)
	if err := pl.Resolve(); err != nil {
		t.Fatal(err)
	}
	for k, v := range pl.Install {
		if strings.Contains(v.Version, "bpo") {
			t.Errorf("%s pulled from backports (%s)", k, v.Version)
		}
	}
}

func TestDependencyFallsBackToBackportsWhenNeeded(t *testing.T) {
	e := setupPins(t)
	db := newTestDB(
		from(e.trixie, "Package: app", "Version: 1", "Depends: lib (>= 2)"),
		from(e.trixie, "Package: lib", "Version: 1"),
		from(e.bpo, "Package: lib", "Version: 3~bpo13+1"),
	)
	pl := db.NewPlan(ResolveOpts{Upgrade: true})
	p, _ := resolveRequest(db, "app")
	pl.Add(p, true)
	if err := pl.Resolve(); err != nil {
		t.Fatal(err)
	}
	if pl.Install["lib"] == nil || pl.Install["lib"].Version != "3~bpo13+1" {
		t.Errorf("lib=%v", pl.Install["lib"])
	}
}

func TestTargetReleaseDependencies(t *testing.T) {
	e := setupPins(t)
	cfg.TargetRelease = "trixie-backports"
	db := newTestDB(
		from(e.trixie, "Package: zfs", "Version: 1", "Depends: lib"),
		from(e.bpo, "Package: zfs", "Version: 2~bpo13+1", "Depends: lib"),
		from(e.trixie, "Package: lib", "Version: 1"),
		from(e.bpo, "Package: lib", "Version: 2~bpo13+1"),
		from(e.trixie, "Package: other", "Version: 1"),
	)
	pl := db.NewPlan(ResolveOpts{Upgrade: true})
	p, _ := resolveRequest(db, "zfs")
	pl.Add(p, true)
	if err := pl.Resolve(); err != nil {
		t.Fatal(err)
	}
	if pl.Install["zfs"].Version != "2~bpo13+1" || pl.Install["lib"].Version != "2~bpo13+1" {
		t.Errorf("zfs=%s lib=%s", pl.Install["zfs"].Version, pl.Install["lib"].Version)
	}
	if v := candVersion(db, "other"); v != "1" {
		t.Errorf("package missing from target release must stay on trixie, got %q", v)
	}
}

func TestPinnedPackageAt500FromBackports(t *testing.T) {
	e := setupPins(t)
	writePrefs(t, "zfs", "Package: zfsutils-linux zfs-dkms\nPin: release n=trixie-backports\nPin-Priority: 500\n")
	db := newTestDB(
		from(e.trixie, "Package: zfsutils-linux", "Version: 2.3"),
		from(e.bpo, "Package: zfsutils-linux", "Version: 2.4~bpo13+1"),
		from(e.bpo, "Package: zfs-dkms", "Version: 2.4~bpo13+1"),
		from(e.trixie, "Package: samba", "Version: 4.22"),
		from(e.bpo, "Package: samba", "Version: 4.24~bpo13+1"),
	)
	if v := candVersion(db, "zfsutils-linux"); v != "2.4~bpo13+1" {
		t.Errorf("zfsutils-linux %q", v)
	}
	if v := candVersion(db, "zfs-dkms"); v != "2.4~bpo13+1" {
		t.Errorf("zfs-dkms %q", v)
	}
	if v := candVersion(db, "samba"); v != "4.22" {
		t.Errorf("samba %q", v)
	}
}

func TestMultipleSourcesShareVersion(t *testing.T) {
	e := setupPins(t)
	sec := &Source{URI: "http://deb.debian.org/debian-security", Suite: "trixie-security", Comp: "main"}
	db := newTestDB(
		from(e.trixie, "Package: pkg", "Version: 1"),
		from(sec, "Package: pkg", "Version: 1"),
	)
	if n := len(db.Avail["pkg"]); n != 1 {
		t.Fatalf("versions=%d", n)
	}
	if n := len(db.Avail["pkg"][0].sources()); n != 2 {
		t.Errorf("sources=%d", n)
	}
	if l := srcLabel(db.Avail["pkg"][0]); l != "Debian:13.7/stable, trixie-security/main" {
		t.Errorf("label %q", l)
	}
	db2 := newTestDB(from(e.bpo, "Package: pkg", "Version: 1"))
	if l := srcLabel(db2.Avail["pkg"][0]); l != "Debian Backports:stable-backports" {
		t.Errorf("label %q", l)
	}
}

func TestLocalDebWins(t *testing.T) {
	e := setupPins(t)
	local := mkPkg("Package: pkg", "Version: 0.1")
	local.LocalDeb = "/x.deb"
	db := newTestDB(from(e.trixie, "Package: pkg", "Version: 1"), local)
	if c := db.Candidate("pkg"); c != local {
		t.Errorf("local deb should win, got %v", c)
	}
}

func TestParsePrefs(t *testing.T) {
	ps := parsePrefs("Explanation: x\nPackage: a b, c*\nPin: release a=stable\nPin-Priority: 990\n\nPackage: *\nPin: origin \"deb.debian.org\"\nPin-Priority: -10\n\nPackage: *\nPin: version 1\nPin-Priority: 5\n\nPackage: x\nPin: release a=x\n")
	if len(ps) != 2 {
		t.Fatalf("stanzas=%d %+v", len(ps), ps)
	}
	if strings.Join(ps[0].names, "|") != "a|b|c*" || ps[0].kind != "release" || ps[0].data != "a=stable" || ps[0].prio != 990 {
		t.Errorf("%+v", ps[0])
	}
	if !ps[1].star() || ps[1].kind != "origin" || ps[1].data != "deb.debian.org" || ps[1].prio != -10 {
		t.Errorf("%+v", ps[1])
	}
}

func TestReadAptConf(t *testing.T) {
	m := map[string]string{}
	readAptConf("# c\n// d\n/* e */\nAPT::Install-Recommends \"false\";\nAPT {\n  Default-Release \"trixie\";\n  Get { Assume-Yes \"true\"; };\n};\nDir::Etc \"x\";\n", m)
	want := map[string]string{"apt::install-recommends": "false", "apt::default-release": "trixie", "apt::get::assume-yes": "true", "dir::etc": "x"}
	for k, v := range want {
		if m[k] != v {
			t.Errorf("%s=%q want %q (%v)", k, m[k], v, m)
		}
	}
}

func TestGlobMatch(t *testing.T) {
	cases := []struct {
		pat, s string
		want   bool
	}{
		{"sam*", "samba", true}, {"sam*", "ksamba", false}, {"/^k/", "ksamba", true}, {"A=*", "a=x", true},
		{"13*", "13.7", true}, {"13", "13.7", false}, {"", "", true}, {"", "x", false}, {"s?mba", "samba", true},
	}
	for _, c := range cases {
		if got := globMatch(c.pat, c.s); got != c.want {
			t.Errorf("globMatch(%q,%q)=%v", c.pat, c.s, got)
		}
	}
}

func TestParseTargetReleaseFlags(t *testing.T) {
	saved := cfg
	defer func() { cfg = saved }()
	for _, args := range [][]string{{"-t", "x"}, {"--target-release", "x"}, {"--target-release=x"}, {"-tx"}, {"-t=x"}, {"-o", "APT::Default-Release=x"}} {
		cfg.TargetRelease = ""
		rest := parseCommon(append(append([]string{}, args...), "install", "foo"))
		if cfg.TargetRelease != "x" {
			t.Errorf("%v -> %q", args, cfg.TargetRelease)
		}
		if len(rest) != 2 || rest[0] != "install" {
			t.Errorf("%v rest=%v", args, rest)
		}
	}
}

func TestRankedOrder(t *testing.T) {
	e := setupPins(t)
	db := newTestDB(
		from(e.bpo, "Package: p", "Version: 3~bpo13+1"),
		from(e.trixie, "Package: p", "Version: 2"),
		from(e.trixie, "Package: p", "Version: 1"),
	)
	var vs []string
	for _, p := range db.Ranked("p") {
		vs = append(vs, p.Version)
	}
	if strings.Join(vs, ",") != "2,1,3~bpo13+1" {
		t.Errorf("ranked %v", vs)
	}
}

func TestHostOf(t *testing.T) {
	for _, u := range []string{"http://deb.debian.org/debian", "https://user:pw@mirror.example:8443/x?y#z", "http://[::1]:8080/debian", "http://[fe80::1]/", "http://10.0.0.1:3142/debian", "file:///srv/repo", "cdrom:[Debian]/", "http://host", "HTTP://Host.Example/p", "http://a.b?q=1"} {
		want := ""
		if p, err := url.Parse(u); err == nil && p.Host != "" {
			want = p.Hostname()
		}
		if got := hostOf(u); got != want {
			t.Errorf("hostOf(%q) = %q, want %q", u, got, want)
		}
	}
}
