package main

// `apk` on KwickOS: run Alpine Linux's own package manager next to apt.
//
// The base image carries only the Alpine public keys and a seeded apk
// database (a virtual "kwick-base" package that provides busybox,
// /bin/sh, alpine-baselayout, ...). The 5 MB apk.static binary is fetched
// from the Alpine mirror on first use and verified exactly like apk itself
// verifies packages: RSA signature over the control segment with a key from
// /etc/apk/keys, then the SHA-256 "datahash" of the data segment.
// Alpine (musl) and Debian (glibc) packages coexist: their dynamic loaders
// have different names (/lib/ld-musl-*.so.1 vs /lib*/ld-linux-*.so.*).

import (
	"archive/tar"
	"bufio"
	"bytes"
	"compress/gzip"
	"crypto"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/asn1"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"math/big"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
)

const apkStatic = "usr/lib/kwick/apk.static"

func alpineArch() string {
	switch runtime.GOARCH {
	case "amd64":
		return "x86_64"
	case "arm64":
		return "aarch64"
	case "riscv64":
		return "riscv64"
	case "arm":
		return "armv7"
	case "386":
		return "x86"
	}
	return runtime.GOARCH
}

func mainApk(args []string) int {
	setupPaths()
	bin := filepath.Join(cfg.Root, apkStatic)
	if _, err := os.Stat(bin); err != nil {
		if os.Geteuid() != 0 {
			fmt.Fprintln(os.Stderr, "apk: first use downloads Alpine's apk-tools; run as root once")
			return 1
		}
		if err := bootstrapApk(bin); err != nil {
			fmt.Fprintln(os.Stderr, "apk: bootstrap failed:", err)
			return 1
		}
	}
	args, gerr := guardApkAdd(bin, args)
	if gerr != nil {
		fmt.Fprintln(os.Stderr, "ERROR:", gerr)
		return 1
	}
	argv := append([]string{"apk"}, args...)
	if err := syscall.Exec(bin, argv, os.Environ()); err != nil {
		fmt.Fprintln(os.Stderr, "apk:", err)
		return 1
	}
	return 0
}

func alpineMainRepo() (string, error) {
	data, err := os.ReadFile(filepath.Join(cfg.Root, "etc/apk/repositories"))
	if err != nil {
		return "", err
	}
	for _, l := range strings.Split(string(data), "\n") {
		l = strings.TrimSpace(l)
		if l != "" && !strings.HasPrefix(l, "#") && strings.HasSuffix(l, "/main") {
			return strings.Replace(l, "https://", "http://", 1), nil
		}
	}
	return "", errors.New("no .../main repository in /etc/apk/repositories")
}

func fetchAll(url string, limit int64) ([]byte, error) {
	resp, err := httpGet(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	return io.ReadAll(io.LimitReader(resp.Body, limit))
}

func bootstrapApk(dst string) error {
	repo, err := alpineMainRepo()
	if err != nil {
		return err
	}
	arch := alpineArch()
	idx, err := fetchAll(repo+"/"+arch+"/APKINDEX.tar.gz", 64<<20)
	if err != nil {
		return err
	}
	ver := ""
	segs, err := gzipMembers(idx)
	if err != nil {
		return err
	}
	for _, seg := range segs {
		forEachTar(seg, func(name string, data []byte) {
			if name != "APKINDEX" {
				return
			}
			for _, para := range strings.Split(string(data), "\n\n") {
				if strings.Contains(para, "\nP:apk-tools-static\n") || strings.HasPrefix(para, "P:apk-tools-static\n") {
					for _, l := range strings.Split(para, "\n") {
						if strings.HasPrefix(l, "V:") {
							ver = l[2:]
						}
					}
				}
			}
		})
	}
	if ver == "" {
		return errors.New("apk-tools-static not found in APKINDEX")
	}
	url := fmt.Sprintf("%s/%s/apk-tools-static-%s.apk", repo, arch, ver)
	fmt.Fprintf(os.Stderr, "apk: fetching Alpine apk-tools %s (one time)\n", ver)
	pkg, err := fetchAll(url, 64<<20)
	if err != nil {
		return err
	}
	bin, err := verifyApk(pkg, "sbin/apk.static")
	if err != nil {
		return fmt.Errorf("%s: %w", url, err)
	}
	os.MkdirAll(filepath.Dir(dst), 0755)
	tmp := dst + ".new"
	if err := os.WriteFile(tmp, bin, 0755); err != nil {
		return err
	}
	return os.Rename(tmp, dst)
}

// gzipMembers splits concatenated gzip streams, returning the raw bytes of
// each member (signatures cover the compressed bytes).
func gzipMembers(b []byte) ([][]byte, error) {
	var out [][]byte
	r := bytes.NewReader(b)
	for r.Len() > 0 {
		start := len(b) - r.Len()
		zr, err := gzip.NewReader(r)
		if err != nil {
			return nil, err
		}
		zr.Multistream(false)
		if _, err := io.Copy(io.Discard, zr); err != nil {
			return nil, err
		}
		out = append(out, b[start:len(b)-r.Len()])
	}
	return out, nil
}

func forEachTar(member []byte, fn func(name string, data []byte)) error {
	zr, err := gzip.NewReader(bytes.NewReader(member))
	if err != nil {
		return err
	}
	zr.Multistream(false)
	tr := tar.NewReader(bufio.NewReader(zr))
	for {
		h, err := tr.Next()
		if err != nil {
			if err == io.EOF || errors.Is(err, io.ErrUnexpectedEOF) {
				return nil
			}
			return nil // apk control segments are truncated tars
		}
		if h.Typeflag == tar.TypeReg || h.Typeflag == tar.TypeRegA {
			data, _ := io.ReadAll(io.LimitReader(tr, 64<<20))
			fn(h.Name, data)
		}
	}
}

type pkixPub struct {
	Algo      asn1.RawValue
	PublicKey asn1.BitString
}

type rsaPubASN struct {
	N *big.Int
	E int
}

func loadApkKey(name string) (*rsaKey, error) {
	data, err := os.ReadFile(filepath.Join(cfg.Root, "etc/apk/keys", filepath.Base(name)))
	if err != nil {
		return nil, fmt.Errorf("untrusted signing key %s", name)
	}
	blk, _ := pem.Decode(data)
	if blk == nil {
		return nil, errors.New("bad PEM key " + name)
	}
	var spki pkixPub
	if _, err := asn1.Unmarshal(blk.Bytes, &spki); err != nil {
		return nil, err
	}
	var pub rsaPubASN
	if _, err := asn1.Unmarshal(spki.PublicKey.Bytes, &pub); err != nil {
		return nil, err
	}
	return &rsaKey{N: pub.N, E: pub.E}, nil
}

// verifyApk checks an Alpine v2 package and returns file `want` from it.
func verifyApk(pkg []byte, want string) ([]byte, error) {
	segs, err := gzipMembers(pkg)
	if err != nil {
		return nil, err
	}
	if len(segs) < 3 {
		return nil, errors.New("not a signed apk package")
	}
	var sigName string
	var sig []byte
	forEachTar(segs[0], func(name string, data []byte) {
		if strings.HasPrefix(name, ".SIGN.") {
			sigName, sig = name, data
		}
	})
	if sig == nil {
		return nil, errors.New("package is not signed")
	}
	var h crypto.Hash
	var digest []byte
	switch {
	case strings.HasPrefix(sigName, ".SIGN.RSA256."):
		s := sha256.Sum256(segs[1])
		h, digest = crypto.SHA256, s[:]
		sigName = strings.TrimPrefix(sigName, ".SIGN.RSA256.")
	case strings.HasPrefix(sigName, ".SIGN.RSA."):
		s := sha1.Sum(segs[1])
		h, digest = crypto.SHA1, s[:]
		sigName = strings.TrimPrefix(sigName, ".SIGN.RSA.")
	default:
		return nil, errors.New("unsupported signature " + sigName)
	}
	key, err := loadApkKey(sigName)
	if err != nil {
		return nil, err
	}
	if !rsaVerifyPKCS1v15(key, h, digest, sig) {
		return nil, errors.New("BAD signature")
	}
	datahash := ""
	forEachTar(segs[1], func(name string, data []byte) {
		if name == ".PKGINFO" {
			for _, l := range strings.Split(string(data), "\n") {
				if v, ok := strings.CutPrefix(l, "datahash = "); ok {
					datahash = strings.TrimSpace(v)
				}
			}
		}
	})
	data := bytes.Join(segs[2:], nil)
	if sum := sha256.Sum256(data); datahash == "" || hex.EncodeToString(sum[:]) != datahash {
		return nil, errors.New("data hash mismatch")
	}
	var out []byte
	forEachTar(data, func(name string, d []byte) {
		if strings.TrimPrefix(name, "./") == want {
			out = d
		}
	})
	if out == nil {
		return nil, errors.New(want + " not found in package")
	}
	return out, nil
}
