package main

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha512"
	"math/big"
	"testing"
)

func TestCompareVersions(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		{"1.0", "1.0", 0}, {"1.0", "1.1", -1}, {"1:1.0", "2.0", 1}, {"1.0~rc1", "1.0", -1},
		{"1.0-1", "1.0-2", -1}, {"1.0+b1", "1.0", 1}, {"2.41-12+deb13u4", "2.41-12", 1},
		{"1.69~deb13u1", "1.54~", 1}, {"9.7-3", "8.0", 1}, {"1.0a", "1.0", 1}, {"1.0", "1.0.0", -1},
		{"0:1.0", "1.0", 0}, {"1.10", "1.9", 1}, {"1.0~~", "1.0~", -1},
	}
	for _, c := range cases {
		if got := CompareVersions(c.a, c.b); got != c.want {
			t.Errorf("CompareVersions(%q,%q)=%d want %d", c.a, c.b, got, c.want)
		}
	}
}

func TestParseDeps(t *testing.T) {
	d := ParseDeps("libc6 (>= 2.38), debconf (>= 0.5) | debconf-2.0, foo [!amd64], bar [amd64] <!nocheck>, baz:any", "amd64")
	if len(d) != 4 {
		t.Fatalf("groups=%d %v", len(d), d)
	}
	if d[0][0].Name != "libc6" || d[0][0].Op != ">=" || d[0][0].Ver != "2.38" {
		t.Errorf("bad dep %v", d[0][0])
	}
	if len(d[1]) != 2 || d[1][1].Name != "debconf-2.0" {
		t.Errorf("bad alternatives %v", d[1])
	}
	if d[2][0].Name != "bar" || d[3][0].Arch != "any" {
		t.Errorf("bad arch handling %v", d)
	}
}

func TestRSAVerify(t *testing.T) {
	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	digest := sha512.Sum512([]byte("hello kwick"))
	sig, err := rsa.SignPKCS1v15(nil, priv, crypto.SHA512, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	k := &rsaKey{N: priv.N, E: priv.E}
	if !rsaVerifyPKCS1v15(k, crypto.SHA512, digest[:], sig) {
		t.Fatal("valid signature rejected")
	}
	sig[10] ^= 1
	if rsaVerifyPKCS1v15(k, crypto.SHA512, digest[:], sig) {
		t.Fatal("corrupted signature accepted")
	}
	other := sha512.Sum512([]byte("other"))
	sig[10] ^= 1
	if rsaVerifyPKCS1v15(k, crypto.SHA512, other[:], sig) {
		t.Fatal("wrong digest accepted")
	}
	if rsaVerifyPKCS1v15(&rsaKey{N: new(big.Int).Add(priv.N, big.NewInt(2)), E: priv.E}, crypto.SHA512, digest[:], sig) {
		t.Fatal("wrong key accepted")
	}
}

func TestResolveInRoot(t *testing.T) {
	root := t.TempDir()
	if p, _ := resolveInRoot(root, "/a/../../etc/passwd", false); p != root+"/etc/passwd" {
		t.Errorf("escaped root: %s", p)
	}
}
