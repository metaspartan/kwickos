package main

import (
	"bytes"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/sha512"
	"crypto/x509"
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
	k := &rsaKey{N: priv.N.Bytes(), E: priv.E}
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
	if rsaVerifyPKCS1v15(&rsaKey{N: new(big.Int).Add(priv.N, big.NewInt(2)).Bytes(), E: priv.E}, crypto.SHA512, digest[:], sig) {
		t.Fatal("wrong key accepted")
	}
}

func TestParseRSASPKI(t *testing.T) {
	for _, bitsN := range []int{1024, 2048, 4096} {
		priv, err := rsa.GenerateKey(rand.Reader, bitsN)
		if err != nil {
			t.Fatal(err)
		}
		der, err := x509.MarshalPKIXPublicKey(&priv.PublicKey)
		if err != nil {
			t.Fatal(err)
		}
		k := parseRSASPKI(der)
		if k == nil || new(big.Int).SetBytes(k.N).Cmp(priv.N) != 0 || k.E != priv.E {
			t.Fatalf("%d-bit key parsed wrong", bitsN)
		}
		digest := sha256.Sum256([]byte("apk"))
		sig, _ := rsa.SignPKCS1v15(nil, priv, crypto.SHA256, digest[:])
		if !rsaVerifyPKCS1v15(k, crypto.SHA256, digest[:], sig) {
			t.Fatal("valid apk-style signature rejected")
		}
		for i := range der {
			parseRSASPKI(der[:i])
		}
	}
	if parseRSASPKI([]byte{0x30, 0x84, 0xff, 0xff, 0xff, 0xff}) != nil {
		t.Fatal("garbage accepted")
	}
}

func refRSAVerify(n *big.Int, e int, h crypto.Hash, digest, sig []byte) bool {
	size := (n.BitLen() + 7) / 8
	prefix, ok := digestInfoPrefix[h]
	if !ok || len(sig) != size || e < 3 {
		return false
	}
	s := new(big.Int).SetBytes(sig)
	if s.Cmp(n) >= 0 {
		return false
	}
	em := new(big.Int).Exp(s, big.NewInt(int64(e)), n).FillBytes(make([]byte, size))
	tLen := len(prefix) + len(digest)
	if size < tLen+11 || em[0] != 0 || em[1] != 1 || em[size-tLen-1] != 0 {
		return false
	}
	for _, b := range em[2 : size-tLen-1] {
		if b != 0xff {
			return false
		}
	}
	return string(em[size-tLen:]) == string(prefix)+string(digest)
}

func testRSAKey(t *testing.T, bitsN, e int) (*big.Int, *big.Int) {
	E := big.NewInt(int64(e))
	one := big.NewInt(1)
	for {
		p, err := rand.Prime(rand.Reader, bitsN/2)
		if err != nil {
			t.Fatal(err)
		}
		q, _ := rand.Prime(rand.Reader, bitsN/2)
		n := new(big.Int).Mul(p, q)
		phi := new(big.Int).Mul(new(big.Int).Sub(p, one), new(big.Int).Sub(q, one))
		d := new(big.Int).ModInverse(E, phi)
		if n.BitLen() == bitsN && d != nil {
			return n, d
		}
	}
}

func TestRSAVerifyDifferential(t *testing.T) {
	digest := sha256.Sum256([]byte("Release"))
	prefix := digestInfoPrefix[crypto.SHA256]
	for _, bitsN := range []int{2048, 3072, 4096} {
		for _, e := range []int{3, 65537} {
			n, d := testRSAKey(t, bitsN, e)
			size := bitsN / 8
			em := make([]byte, size)
			em[1] = 1
			for i := 2; i < size-len(prefix)-len(digest)-1; i++ {
				em[i] = 0xff
			}
			copy(em[size-len(prefix)-len(digest):], prefix)
			copy(em[size-len(digest):], digest[:])
			valid := new(big.Int).Exp(new(big.Int).SetBytes(em), d, n).FillBytes(make([]byte, size))
			k := &rsaKey{N: n.Bytes(), E: e}
			flip := append([]byte(nil), valid...)
			flip[size/2] ^= 0x40
			random := make([]byte, size)
			rand.Read(random)
			cases := map[string][]byte{
				"valid":     valid,
				"flipped":   flip,
				"random":    random,
				"zero":      make([]byte, size),
				"equal N":   n.FillBytes(make([]byte, size)),
				"N+1":       new(big.Int).Add(n, big.NewInt(1)).FillBytes(make([]byte, size)),
				"all ones":  bytes.Repeat([]byte{0xff}, size),
				"short":     valid[1:],
				"long":      append([]byte{0}, valid...),
				"N-1":       new(big.Int).Sub(n, big.NewInt(1)).FillBytes(make([]byte, size)),
				"valid*2^k": new(big.Int).Mod(new(big.Int).Lsh(new(big.Int).SetBytes(valid), 8), n).FillBytes(make([]byte, size)),
			}
			for name, sig := range cases {
				got := rsaVerifyPKCS1v15(k, crypto.SHA256, digest[:], sig)
				if want := refRSAVerify(n, e, crypto.SHA256, digest[:], sig); got != want || got != (name == "valid") {
					t.Errorf("%d-bit e=%d %s: got %v, math/big %v", bitsN, e, name, got, want)
				}
			}
			for i := 0; i < 20; i++ {
				x, _ := rand.Int(rand.Reader, n)
				want := new(big.Int).Exp(x, big.NewInt(int64(e)), n).FillBytes(make([]byte, size))
				if got := modExp(x.FillBytes(make([]byte, size)), uint64(e), k.N); !bytes.Equal(got, want) {
					t.Fatalf("%d-bit e=%d: modExp differs from math/big", bitsN, e)
				}
			}
		}
	}
}

func TestModExp(t *testing.T) {
	for i := 0; i < 400; i++ {
		bitsN := 8 + i*13%4100
		m, _ := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), uint(bitsN)))
		m.SetBit(m, 0, 1)
		if m.BitLen() < 2 {
			continue
		}
		x, _ := rand.Int(rand.Reader, m)
		if i%7 == 0 {
			x.Sub(m, big.NewInt(1))
		}
		var e uint64
		switch i % 4 {
		case 0:
			e = 3
		case 1:
			e = 65537
		case 2:
			e = 1
		default:
			eb, _ := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 64))
			e = eb.Uint64() | 1
		}
		size := (m.BitLen() + 7) / 8
		want := new(big.Int).Exp(x, new(big.Int).SetUint64(e), m).FillBytes(make([]byte, size))
		if got := modExp(x.FillBytes(make([]byte, size)), e, m.Bytes()); string(got) != string(want) {
			t.Fatalf("modExp mismatch for %d-bit modulus, e=%d", m.BitLen(), e)
		}
	}
}

func TestResolveInRoot(t *testing.T) {
	root := t.TempDir()
	if p, _ := resolveInRoot(root, "/a/../../etc/passwd", false); p != root+"/etc/passwd" {
		t.Errorf("escaped root: %s", p)
	}
}
