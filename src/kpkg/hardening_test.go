package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func bombSetup(t *testing.T, body []byte) (*Source, string) {
	setupMA(t)
	t.Setenv("http_proxy", "")
	t.Setenv("HTTP_PROXY", "")
	cfg.Lists = t.TempDir()
	return &Source{URI: "http://example.invalid", Suite: "trixie", Comp: "main"}, serve(t, string(body)) + "/"
}

func gzipBytes(t *testing.T, raw []byte) []byte {
	t.Helper()
	var b bytes.Buffer
	zw := gzip.NewWriter(&b)
	zw.Write(raw)
	zw.Close()
	return b.Bytes()
}

func TestFetchIndexRejectsDecompressionBomb(t *testing.T) {
	raw := bytes.Repeat([]byte("Package: a\n"), 8<<20)
	gz := gzipBytes(t, raw)
	s, base := bombSetup(t, gz)
	sum := sha256.Sum256(gz)
	small := sha256.Sum256([]byte("x"))
	name := "main/binary-amd64/Packages"
	signed := map[string]relEntry{
		name + ".gz": {hex.EncodeToString(sum[:]), int64(len(gz))},
		name:         {hex.EncodeToString(small[:]), 4096},
	}
	_, err := fetchIndex(s, "amd64", base, signed, false, &progress{})
	if err == nil || !strings.Contains(err.Error(), "larger than expected") {
		t.Fatalf("bomb within the signed size accepted: %v", err)
	}
	if _, err := os.Stat(s.indexPath("amd64")); err == nil {
		t.Fatal("bomb cached")
	}
	unsized := map[string]relEntry{name + ".gz": {hex.EncodeToString(sum[:]), int64(len(gz))}}
	_, err = fetchIndex(s, "amd64", base, unsized, false, &progress{})
	if err == nil || !strings.Contains(err.Error(), "larger than expected") {
		t.Fatalf("bomb accepted without a signed uncompressed size: %v", err)
	}
	left, _ := filepath.Glob(filepath.Join(cfg.Lists, ".dl-*"))
	if len(left) != 0 {
		t.Fatalf("temp files left: %v", left)
	}
}

func TestFetchIndexVerifiesHashBeforeDecompressing(t *testing.T) {
	gz := gzipBytes(t, bytes.Repeat([]byte("Package: a\n"), 1<<20))
	s, base := bombSetup(t, gz)
	name := "main/binary-amd64/Packages.gz"
	hashes := map[string]relEntry{name: {strings.Repeat("0", 64), int64(len(gz))}}
	_, err := fetchIndex(s, "amd64", base, hashes, false, &progress{})
	if err == nil || !strings.Contains(err.Error(), "hash sum mismatch") {
		t.Fatalf("unsigned bytes reached the decompressor: %v", err)
	}
}

func TestFetchIndexAcceptsExactSignedSize(t *testing.T) {
	idx := "Package: a\nVersion: 1\nArchitecture: amd64\n\n"
	gz := gzipBytes(t, []byte(idx))
	s, base := bombSetup(t, gz)
	sum := sha256.Sum256(gz)
	plain := sha256.Sum256([]byte(idx))
	name := "main/binary-amd64/Packages"
	hashes := map[string]relEntry{
		name + ".gz": {hex.EncodeToString(sum[:]), int64(len(gz))},
		name:         {hex.EncodeToString(plain[:]), int64(len(idx))},
	}
	if _, err := fetchIndex(s, "amd64", base, hashes, false, &progress{}); err != nil {
		t.Fatal(err)
	}
	if got, err := readKidx(s.indexPath("amd64")); err != nil || got != idx {
		t.Fatalf("cached index %q %v", got, err)
	}
}

type rawEntry struct {
	name, link, body string
}

func rawTarDeb(t *testing.T, ents []rawEntry) string {
	t.Helper()
	var b bytes.Buffer
	tw := tar.NewWriter(&b)
	for _, e := range ents {
		h := &tar.Header{Name: e.name, Mode: 0644}
		if e.link != "" {
			h.Typeflag, h.Linkname, h.Mode = tar.TypeSymlink, e.link, 0777
		} else {
			h.Typeflag, h.Size = tar.TypeReg, int64(len(e.body))
		}
		if err := tw.WriteHeader(h); err != nil {
			t.Fatal(err)
		}
		tw.Write([]byte(e.body))
	}
	tw.Close()
	dir := t.TempDir()
	tarPath := filepath.Join(dir, "data.tar")
	os.WriteFile(tarPath, b.Bytes(), 0644)
	deb := filepath.Join(dir, "x.deb")
	preTar.Store(deb, tarPath)
	t.Cleanup(func() { preTar.Delete(deb) })
	return deb
}

func TestApkConflictThroughSymlinkShippedInDeb(t *testing.T) {
	apkRoot(t, true)
	deb := rawTarDeb(t, []rawEntry{{name: "./opt/x", link: "/usr/bin"}, {name: "./opt/x/jq", body: "evil"}})
	err := testTx().checkApkConflicts(&Pkg{Name: "x", Version: "1"}, deb)
	if err == nil || !strings.Contains(err.Error(), "'/opt/x/jq', which is also in Alpine (apk) package jq") {
		t.Fatalf("symlink shipped in the deb bypassed the apk check: %v", err)
	}
	rel := rawTarDeb(t, []rawEntry{{name: "./opt/y", link: "../usr/bin"}, {name: "./opt/y/jq", body: "evil"}})
	if err := testTx().checkApkConflicts(&Pkg{Name: "y", Version: "1"}, rel); err == nil {
		t.Fatal("relative symlink shipped in the deb bypassed the apk check")
	}
	ok := rawTarDeb(t, []rawEntry{{name: "./opt/z", link: "/usr/lib"}, {name: "./opt/z/jq", body: "fine"}})
	if err := testTx().checkApkConflicts(&Pkg{Name: "z", Version: "1"}, ok); err != nil {
		t.Fatalf("harmless symlink flagged: %v", err)
	}
}

func TestApkConflictExemptsFilesOwnedByDpkg(t *testing.T) {
	apkRoot(t, true)
	deb := buildTestDeb(t, "jq", map[string]string{"/usr/bin/jq": "debian jq"}, 0)
	p := &Pkg{Name: "jq", Version: "1.7.1-2"}
	tx := testTx()
	tx.owners = map[string][]string{"/usr/bin/jq": {"jq"}}
	if err := tx.checkApkConflicts(p, deb); err != nil {
		t.Fatalf("upgrade of the package that already owns the file refused: %v", err)
	}
	tx = testTx()
	tx.owners = map[string][]string{"/usr/bin/oldtool": {"oldtool"}}
	old := buildTestDeb(t, "oldtool", map[string]string{"/bin/oldtool": "x"}, 0)
	if err := tx.checkApkConflicts(&Pkg{Name: "oldtool"}, old); err != nil {
		t.Fatalf("file owned through the usr-merge link refused: %v", err)
	}
	if err := testTx().checkApkConflicts(p, deb); err == nil {
		t.Fatal("unowned file no longer reported")
	}
}

func TestApkConflictUsesDpkgDatabase(t *testing.T) {
	apkRoot(t, true)
	os.MkdirAll(filepath.Join(cfg.Admin, "info"), 0755)
	os.WriteFile(filepath.Join(cfg.Admin, "info", "jq.list"), []byte("/usr/bin/jq\n"), 0644)
	tx := testTx()
	tx.db.Installed["jq"] = &Installed{Pkg: &Pkg{Name: "jq"}}
	deb := buildTestDeb(t, "jq", map[string]string{"/usr/bin/jq": "debian jq"}, 0)
	if err := tx.checkApkConflicts(&Pkg{Name: "jq", Version: "2"}, deb); err != nil {
		t.Fatalf("file recorded in the dpkg database refused: %v", err)
	}
}

func TestWgetVerifiesCertificatesUnlessBareBusyBox(t *testing.T) {
	savedBB, savedSSL := wgetIsBusyBox, haveOpenssl
	t.Cleanup(func() { wgetIsBusyBox, haveOpenssl = savedBB, savedSSL })
	cases := []struct {
		busybox, openssl, insecure bool
	}{
		{false, false, false},
		{false, true, false},
		{true, true, false},
		{true, false, true},
	}
	for _, c := range cases {
		wgetIsBusyBox = func(string) bool { return c.busybox }
		haveOpenssl = func() bool { return c.openssl }
		args := wgetArgs("wget", "https://x/y")
		if got := strings.Contains(strings.Join(args, " "), "--no-check-certificate"); got != c.insecure {
			t.Errorf("busybox=%v openssl=%v: %v", c.busybox, c.openssl, args)
		}
		if args[len(args)-1] != "https://x/y" {
			t.Errorf("url missing: %v", args)
		}
	}
}

func TestStagedCommitManyFilesSyncsAndRenames(t *testing.T) {
	dir := t.TempDir()
	var s stagedFiles
	for i := 0; i < 40; i++ {
		host := filepath.Join(dir, fmt.Sprintf("d%d", i%3), fmt.Sprintf("f%d", i))
		os.MkdirAll(filepath.Dir(host), 0755)
		h := &tar.Header{ModTime: time.Unix(1700000000, 0)}
		if err := s.add(host, strings.NewReader("data"), 0644, h); err != nil {
			t.Fatal(err)
		}
	}
	if err := s.commit(); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 40; i++ {
		p := filepath.Join(dir, fmt.Sprintf("d%d", i%3), fmt.Sprintf("f%d", i))
		if b, err := os.ReadFile(p); err != nil || string(b) != "data" {
			t.Fatalf("%s: %q %v", p, b, err)
		}
		if _, err := os.Stat(p + ".dpkg-new"); err == nil {
			t.Fatalf("%s left behind", p)
		}
	}
}
