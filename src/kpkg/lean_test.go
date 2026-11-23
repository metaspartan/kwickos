package main

import (
	"math"
	"os"
	"path/filepath"
	"reflect"
	"runtime/debug"
	"strings"
	"sync"
	"testing"

	"github.com/klauspost/compress/gzip"
)

const trickyIndex = "Package: a\nVersion: 1.0\nArchitecture: amd64\nDepends: libc6 (>= 2.38),\n libfoo\nProvides: x, y (= 2)\nDescription: d\n more\n\n" +
	"# comment\nPackage: b\r\nVersion: 2\r\nArchitecture: all\r\nMulti-Arch: foreign\r\nEssential: yes\r\nPre-Depends: c\r\n\r\n" +
	"Package: c\nVersion: 3\nArchitecture: amd64\nBreaks: a  \n (<< 1)\nBreaks: a (<< 2)\nConflicts:\n z\nReplaces: q\nRecommends: r\nSuggests: s\nProtected: yes\n:odd\nX-Custom: v\n\n\n" +
	"Package: d\nVersion: 1\nArchitecture: arm64\n\n" +
	"Package: e\nVersion: 1\nArchitecture: amd64\nDepends: f\n# mid\n cont\nSHA256: abc\n"

func TestLeanIndexMatchesEagerParse(t *testing.T) {
	setupMA(t)
	checkLeanAgainstEager(t, trickyIndex)
	if src := os.Getenv("PKGS"); src != "" {
		f, err := os.Open(src)
		if err != nil {
			t.Fatal(err)
		}
		defer f.Close()
		zr, err := gzip.NewReader(f)
		if err != nil {
			t.Fatal(err)
		}
		var b strings.Builder
		ParseParagraphs(zr, indexKeep, func(p *Paragraph) error { p.Write822(&b); b.WriteString("\n"); return nil })
		checkLeanAgainstEager(t, b.String())
	}
}

func checkLeanAgainstEager(t *testing.T, s string) {
	t.Helper()
	var eager []*Pkg
	parseParagraphString(s, nil, func(p *Paragraph) error {
		if pk := newPkg(p); pk.archOK() {
			eager = append(eager, pk)
		}
		return nil
	})
	lean := parseIndexPkgs(s, nil)
	if len(lean) != len(eager) {
		t.Fatalf("lean parsed %d packages, eager %d", len(lean), len(eager))
	}
	keys := []string{"Package", "Version", "Architecture", "Multi-Arch", "Provides", "Essential", "Protected", "Depends", "Pre-Depends",
		"Recommends", "Suggests", "Conflicts", "Breaks", "Replaces", "Description", "SHA256", "X-Custom", "", "Missing"}
	for i, e := range eager {
		l := lean[i]
		if l.Name != e.Name || l.Version != e.Version || l.Arch != e.Arch {
			t.Fatalf("package %d: lean %s %s %s, eager %s %s %s", i, l.Name, l.Version, l.Arch, e.Name, e.Version, e.Arch)
		}
		for _, k := range keys {
			if got, want := l.Field(k), e.Field(k); got != want {
				t.Fatalf("%s: Field(%q) = %q, want %q", e.Name, k, got, want)
			}
		}
		if !reflect.DeepEqual(l.Provides(), e.Provides()) || !reflect.DeepEqual(l.Deps("Depends"), e.Deps("Depends")) {
			t.Fatalf("%s: parsed relations differ", e.Name)
		}
		if !reflect.DeepEqual(l.P.Fields(), e.P.Keys) || !reflect.DeepEqual(l.P.M, e.P.M) {
			t.Fatalf("%s: lazy paragraph %q differs from %q", e.Name, l.P.M, e.P.M)
		}
		for _, k := range keys {
			if l.P.Get(k) != e.P.Get(k) {
				t.Fatalf("%s: P.Get(%q) differs", e.Name, k)
			}
		}
	}
}

func TestLazyParagraphConcurrentAccess(t *testing.T) {
	p := lazyParagraph("Package: a\nVersion: 1\nDescription: x\n y\n")
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if p.Get("Description") != "x\n y" || len(p.Fields()) != 3 {
				t.Error("bad lazy parse")
			}
		}()
	}
	wg.Wait()
	var b strings.Builder
	p.Write822(&b)
	if b.String() != "Package: a\nVersion: 1\nDescription: x\n y\n" {
		t.Errorf("round trip %q", b.String())
	}
}

func TestKidxFormats(t *testing.T) {
	dir := t.TempDir()
	data := strings.Repeat("Package: p\nVersion: 1\n\n", 5000)
	z := filepath.Join(dir, "z.kidx")
	if err := writeKidx(z, []byte(data)); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(z); !strings.HasPrefix(string(b), string(zstdMagic)) {
		t.Fatal("index cache is not zstd")
	}
	if got, err := readKidx(z); err != nil || got != data {
		t.Fatalf("zstd round trip failed: %v", err)
	}
	g := filepath.Join(dir, "g.kidx")
	f, _ := os.Create(g)
	zw := gzip.NewWriter(f)
	zw.Write([]byte(data))
	zw.Close()
	f.Close()
	if got, err := readKidx(g); err != nil || got != data {
		t.Fatalf("legacy gzip index not readable: %v", err)
	}
	os.WriteFile(z, []byte("\x28\xb5\x2f\xfdgarbage"), 0644)
	if _, err := readKidx(z); err == nil {
		t.Fatal("corrupt zstd index accepted")
	}
}

func TestAddAvailIndexesProviders(t *testing.T) {
	setupMA(t)
	pk := parseIndexPkgs("Package: mawk\nVersion: 1\nArchitecture: amd64\nProvides: awk\n\nPackage: plain\nVersion: 1\nArchitecture: amd64\n", nil)
	db := newTestDB(pk...)
	if len(db.provAvail["awk"]) != 1 || db.provAvail["awk"][0].pkg.Name != "mawk" || len(db.provAvail) != 1 {
		t.Fatalf("providers = %v", db.provAvail)
	}
}

func TestGCTuningCoversIndexHeap(t *testing.T) {
	saved := memTotal
	t.Cleanup(func() { memTotal = saved; debug.SetGCPercent(100); debug.SetMemoryLimit(math.MaxInt64) })
	memTotal = func() int64 { return 512 << 20 }
	tuneGCFor(512 << 20)
	restore := relaxGC()
	if pct := setGCPercentQuery(); pct != -1 {
		t.Errorf("GC still enabled during load: %d", pct)
	}
	restore()
	if pct := setGCPercentQuery(); pct != 50 {
		t.Errorf("GC percent not restored: %d", pct)
	}
	if lim := memLimitQuery(); lim < 192<<20 {
		t.Errorf("low-memory limit %d MiB is below the index heap", lim>>20)
	}
}

func setGCPercentQuery() int {
	p := debug.SetGCPercent(100)
	debug.SetGCPercent(p)
	return p
}

func memLimitQuery() int64 { return debug.SetMemoryLimit(-1) }
