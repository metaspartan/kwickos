package main

import (
	"archive/tar"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestFnmatch(t *testing.T) {
	cases := []struct {
		pat, s string
		want   bool
	}{
		{"/usr/share/doc/*", "/usr/share/doc/curl/copyright", true},
		{"/usr/share/doc/*", "/usr/share/doc", false},
		{"/usr/share/doc/*/copyright", "/usr/share/doc/curl/copyright", true},
		{"/usr/share/doc/*/copyright", "/usr/share/doc/a/b/copyright", true},
		{"/usr/share/locale/*", "/usr/share/locale/de/LC_MESSAGES/curl.mo", true},
		{"/usr/share/man/??/*", "/usr/share/man/de/man1/x.1.gz", true},
		{"/usr/share/man/??/*", "/usr/share/man/man1/x.1.gz", false},
		{"/a/[abc]x", "/a/bx", true},
		{"/a/[!abc]x", "/a/bx", false},
		{"/a/[^abc]x", "/a/dx", true},
		{"/a/[a-c]x", "/a/cx", true},
		{"/a/[]]x", "/a/]x", true},
		{"/a/[[:digit:]]", "/a/7", true},
		{"/a/[[:alpha:]]", "/a/7", false},
		{"/a/\\*", "/a/*", true},
		{"/a/\\*", "/a/b", false},
		{"/a/[x", "/a/[x", true},
		{"*", "/anything/at/all", true},
		{"/usr/*.gz", "/usr/share/x.gz", true},
		{"/usr/*.gz", "/usr/share/x.gzip", false},
		{"/.hidden/*", "/.hidden/.x", true},
	}
	for _, c := range cases {
		if got := fnmatch(c.pat, c.s); got != c.want {
			t.Errorf("fnmatch(%q, %q) = %v, want %v", c.pat, c.s, got, c.want)
		}
	}
}

var slimRules = []filterRule{
	{false, "/usr/share/doc/*"},
	{true, "/usr/share/doc/*/copyright"},
	{false, "/usr/share/groff/*"},
	{false, "/usr/share/info/*"},
	{false, "/usr/share/linda/*"},
	{false, "/usr/share/lintian/overrides/*"},
	{false, "/usr/share/locale/*"},
	{false, "/usr/share/man/*"},
}

func TestFilterSkipSemantics(t *testing.T) {
	f := &pathFilter{rules: slimRules}
	cases := []struct {
		p    string
		typ  byte
		skip bool
	}{
		{"/usr/share/doc/curl/changelog.gz", tar.TypeReg, true},
		{"/usr/share/doc/curl/copyright", tar.TypeReg, false},
		{"/usr/share/doc/curl", tar.TypeDir, false},
		{"/usr/share/doc", tar.TypeDir, false},
		{"/usr/share/doc/libfoo", tar.TypeSymlink, false},
		{"/usr/share/doc/curl/examples", tar.TypeDir, false},
		{"/usr/share/man/man1/curl.1.gz", tar.TypeReg, true},
		{"/usr/share/man/man1", tar.TypeDir, true},
		{"/usr/share/man", tar.TypeDir, false},
		{"/usr/share/locale/de/LC_MESSAGES/x.mo", tar.TypeReg, true},
		{"/usr/bin/curl", tar.TypeReg, false},
	}
	for _, c := range cases {
		if got := f.skip(c.p, c.typ); got != c.skip {
			t.Errorf("skip(%q) = %v, want %v", c.p, got, c.skip)
		}
	}
	order := &pathFilter{rules: []filterRule{{true, "/usr/share/doc/*/copyright"}, {false, "/usr/share/doc/*"}}}
	if !order.skip("/usr/share/doc/curl/copyright", tar.TypeReg) {
		t.Error("an earlier include must not override a later exclude")
	}
	var none *pathFilter
	if none.skip("/usr/share/doc/x", tar.TypeReg) {
		t.Error("nil filter skipped a file")
	}
}

func TestDpkgConfigFilters(t *testing.T) {
	setupMA(t)
	d := filepath.Join(cfg.Root, "etc/dpkg/dpkg.cfg.d")
	os.MkdirAll(d, 0755)
	os.WriteFile(filepath.Join(d, "20-include"), []byte("# keep copyright\npath-include=/usr/share/doc/*/copyright\n"), 0644)
	os.WriteFile(filepath.Join(d, "10-exclude"), []byte("path-exclude /usr/share/doc/*\n  path-exclude = \"/usr/share/man/*\"  \nforce-unsafe-io\n\n"), 0644)
	os.WriteFile(filepath.Join(d, "30-ignored.conf"), []byte("path-exclude /usr/bin/*\n"), 0644)
	os.WriteFile(filepath.Join(d, ".hidden"), []byte("path-exclude /usr/lib/*\n"), 0644)
	os.WriteFile(filepath.Join(cfg.Root, "etc/dpkg/dpkg.cfg"), []byte("path-exclude /usr/share/doc/*/copyright\n"), 0644)
	cfg.PathFilters = []filterRule{{true, "/usr/share/doc/*/copyright"}}
	f := loadPathFilters(cfg.Root)
	want := []filterRule{
		{false, "/usr/share/doc/*"},
		{false, "/usr/share/man/*"},
		{true, "/usr/share/doc/*/copyright"},
		{false, "/usr/share/doc/*/copyright"},
		{true, "/usr/share/doc/*/copyright"},
	}
	if f == nil || !reflect.DeepEqual(f.rules, want) {
		t.Fatalf("rules = %+v", f)
	}
}

func TestDpkgPathOptions(t *testing.T) {
	setupMA(t)
	rest := parseDpkgOpts([]string{"--path-exclude=/usr/share/doc/*", "--path-include", "/usr/share/doc/*/copyright", "--force-overwrite", "-i", "x.deb"})
	if !reflect.DeepEqual(rest, []string{"-i", "x.deb"}) || len(cfg.PathFilters) != 2 || !cfg.PathFilters[1].include || !cfg.ForceOverwrite {
		t.Fatalf("rest %v filters %+v force %v", rest, cfg.PathFilters, cfg.ForceOverwrite)
	}
}

func TestExtractHonoursPathFilters(t *testing.T) {
	setupMA(t)
	deb := buildTestDeb(t, "curl", map[string]string{
		"/usr/bin/curl":                         "bin",
		"/usr/share/doc/curl/copyright":         "license",
		"/usr/share/doc/curl/changelog.gz":      "changes",
		"/usr/share/doc/libcurl4":               "->curl",
		"/usr/share/man/man1/curl.1.gz":         "man",
		"/usr/share/locale/de/LC_MESSAGES/c.mo": "mo",
	}, 0)
	res, err := ExtractData(deb, nil, nil, nil, nil, &pathFilter{rules: slimRules})
	if err != nil {
		t.Fatal(err)
	}
	exists := func(p string) bool { _, err := os.Lstat(filepath.Join(cfg.Root, p)); return err == nil }
	for _, p := range []string{"/usr/bin/curl", "/usr/share/doc/curl/copyright", "/usr/share/doc/libcurl4"} {
		if !exists(p) {
			t.Errorf("%s not installed", p)
		}
	}
	for _, p := range []string{"/usr/share/doc/curl/changelog.gz", "/usr/share/man/man1", "/usr/share/man/man1/curl.1.gz", "/usr/share/locale/de"} {
		if exists(p) {
			t.Errorf("%s installed despite path-exclude", p)
		}
	}
	listed := map[string]bool{}
	for _, f := range res.Files {
		listed[f] = true
	}
	for _, p := range []string{"/usr/share/doc/curl/changelog.gz", "/usr/share/man/man1/curl.1.gz", "/usr/bin/curl"} {
		if !listed[p] {
			t.Errorf("%s missing from the file list (dpkg keeps filtered files listed)", p)
		}
	}
}

func TestFilteredFilesRemoveCleanly(t *testing.T) {
	setupMA(t)
	d := filepath.Join(cfg.Root, "etc/dpkg/dpkg.cfg.d")
	os.MkdirAll(d, 0755)
	os.WriteFile(filepath.Join(d, "slim"), []byte("path-exclude /usr/share/doc/*\npath-include /usr/share/doc/*/copyright\n"), 0644)
	deb := buildTestDeb(t, "tool", map[string]string{"/usr/bin/tool": "x", "/usr/share/doc/tool/README": "r", "/usr/share/doc/tool/copyright": "c"}, 0)
	tx := testTx()
	p := &Pkg{Name: "tool", Version: "1.0", Arch: "amd64"}
	tx.loadOwners()
	if err := tx.unpack(p, deb); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(cfg.Root, "usr/share/doc/tool/README")); err == nil {
		t.Fatal("excluded README written")
	}
	in := tx.db.Installed["tool"]
	if in == nil {
		t.Fatal("not recorded")
	}
	if err := tx.remove(in); err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{"usr/bin/tool", "usr/share/doc/tool/copyright", "usr/share/doc/tool"} {
		if _, err := os.Lstat(filepath.Join(cfg.Root, p)); err == nil {
			t.Errorf("%s left behind after removal", p)
		}
	}
}
