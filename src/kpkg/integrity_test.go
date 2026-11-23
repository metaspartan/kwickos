package main

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

func TestCheckDist(t *testing.T) {
	rel := func(suite, code string) *Paragraph {
		p := NewParagraph()
		if suite != "" {
			p.Set("Suite", suite)
		}
		if code != "" {
			p.Set("Codename", code)
		}
		return p
	}
	cases := []struct {
		suite, code, dist string
		want              bool
	}{
		{"stable", "trixie", "trixie", true},
		{"stable", "trixie", "stable", true},
		{"stable-security", "trixie-security", "trixie-security", true},
		{"oldstable", "bookworm", "trixie", false},
		{"stable", "trixie", "bookworm", false},
		{"stable", "trixie", "trixie-updates", false},
		{"oldoldstable", "buster", "buster/updates", true},
		{"experimental", "rc-buggy", "../project/experimental", true},
		{"", "", "anything", true},
		{"stable", "trixie", "./", true},
	}
	for _, c := range cases {
		if got := checkDist(rel(c.suite, c.code), c.dist); got != c.want {
			t.Errorf("checkDist(Suite %q, Codename %q, %q) = %v, want %v", c.suite, c.code, c.dist, got, c.want)
		}
	}
}

func TestCapReader(t *testing.T) {
	b, err := io.ReadAll(&capReader{r: strings.NewReader("12345"), left: 5, what: "x"})
	if err != nil || string(b) != "12345" {
		t.Fatalf("exact size: %q %v", b, err)
	}
	_, err = io.ReadAll(&capReader{r: strings.NewReader("123456"), left: 5, what: "x"})
	if err == nil || !strings.Contains(err.Error(), "mismatch") {
		t.Fatalf("oversized stream accepted: %v", err)
	}
}

type countingReader struct {
	n int64
}

func (c *countingReader) Read(p []byte) (int, error) {
	for i := range p {
		p[i] = 'x'
	}
	c.n += int64(len(p))
	return len(p), nil
}

func TestCapReaderStopsEndlessStream(t *testing.T) {
	cr := &countingReader{}
	_, err := io.Copy(io.Discard, &capReader{r: cr, left: 1 << 20, what: "x"})
	if err == nil || cr.n > 1<<20+1<<16 {
		t.Fatalf("endless body read %d bytes, err %v", cr.n, err)
	}
}

func serve(t *testing.T, body string) string {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, body) }))
	t.Cleanup(srv.Close)
	return srv.URL
}

func TestFetchToVerification(t *testing.T) {
	setupMA(t)
	t.Setenv("http_proxy", "")
	t.Setenv("HTTP_PROXY", "")
	dir := t.TempDir()
	os.MkdirAll(filepath.Join(dir, "partial"), 0755)
	dst := filepath.Join(dir, "p.deb")
	body := "debian package bytes"
	sum := sha256.Sum256([]byte(body))
	good := hex.EncodeToString(sum[:])
	url := serve(t, body)

	if err := fetchTo(url, dst, "", int64(len(body))); !errors.Is(err, errNoHash) {
		t.Fatalf("package without SHA256 accepted: %v", err)
	}
	if _, err := os.Stat(dst); err == nil {
		t.Fatal("unverified file written")
	}
	if err := fetchTo(url, dst, good, int64(len(body))-3); err == nil {
		t.Fatal("body larger than the index Size accepted")
	}
	if err := fetchTo(url, dst, good, int64(len(body))+3); err == nil {
		t.Fatal("short body accepted")
	}
	if err := fetchTo(url, dst, strings.Repeat("0", 64), int64(len(body))); err == nil {
		t.Fatal("hash mismatch accepted")
	}
	if _, err := os.Stat(dst); err == nil {
		t.Fatal("rejected download left in place")
	}
	if err := fetchTo(url, dst, good, int64(len(body))); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(dst); string(b) != body {
		t.Fatalf("got %q", b)
	}
	cfg.AllowUnauth = true
	os.Remove(dst)
	if err := fetchTo(url, dst, "", 0); err != nil {
		t.Fatalf("--allow-unauthenticated: %v", err)
	}
}

func TestFetchIndexEnforcesReleaseSize(t *testing.T) {
	setupMA(t)
	t.Setenv("http_proxy", "")
	t.Setenv("HTTP_PROXY", "")
	cfg.Lists = t.TempDir()
	idx := "Package: a\nVersion: 1\nArchitecture: amd64\n\n"
	sum := sha256.Sum256([]byte(idx))
	base := serve(t, idx) + "/"
	s := &Source{URI: "http://example.invalid", Suite: "trixie", Comp: "main"}
	name := "main/binary-amd64/Packages"
	hashes := map[string]relEntry{name: {hex.EncodeToString(sum[:]), int64(len(idx)) - 1}}
	if _, err := fetchIndex(s, "amd64", base, hashes, false, &progress{}); err == nil || !strings.Contains(err.Error(), "mismatch") {
		t.Fatalf("oversized index accepted: %v", err)
	}
	if _, err := os.Stat(s.indexPath("amd64")); err == nil {
		t.Fatal("oversized index cached")
	}
	hashes[name] = relEntry{hex.EncodeToString(sum[:]), int64(len(idx))}
	if _, err := fetchIndex(s, "amd64", base, hashes, false, &progress{}); err != nil {
		t.Fatal(err)
	}
	if got, err := readKidx(s.indexPath("amd64")); err != nil || got != idx {
		t.Fatalf("cached index %q %v", got, err)
	}
}

func TestLockIsTakenOnceAndReentrant(t *testing.T) {
	setupMA(t)
	u1, err := lockDB()
	if err != nil {
		t.Fatal(err)
	}
	u2, err := lockDB()
	if err != nil {
		t.Fatal(err)
	}
	other := func() error {
		f, err := os.OpenFile(filepath.Join(cfg.Admin, "lock-frontend"), os.O_RDWR, 0)
		if err != nil {
			return err
		}
		defer f.Close()
		return syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
	}
	if other() == nil {
		t.Fatal("lock not held")
	}
	u2()
	if other() == nil {
		t.Fatal("inner unlock released the outer lock")
	}
	u1()
	if err := other(); err != nil {
		t.Fatalf("lock not released: %v", err)
	}
}

func TestExtractLeavesNoStagingFiles(t *testing.T) {
	setupMA(t)
	deb := buildTestDeb(t, "many", map[string]string{"/usr/bin/many": "bin"}, 40)
	res, err := ExtractData(deb, nil, nil, nil, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Files) < 40 {
		t.Fatalf("files %d", len(res.Files))
	}
	filepath.Walk(cfg.Root, func(p string, fi os.FileInfo, err error) error {
		if strings.HasSuffix(p, ".dpkg-new") {
			t.Errorf("leftover %s", p)
		}
		return nil
	})
	if b, _ := os.ReadFile(filepath.Join(cfg.Root, "usr/share/many/f39")); string(b) != "data 39" {
		t.Errorf("staged file not committed: %q", b)
	}
}
