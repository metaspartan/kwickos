package main

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/asn1"
	"encoding/binary"
	"io"
	"math/big"
	"net"
	"net/url"
	"os"
	"os/exec"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/ulikunitz/xz"
)

type fuzzRSAKey struct {
	pub  *rsa.PublicKey
	k    *rsaKey
	d, n *big.Int
}

var (
	fuzzKeysOnce sync.Once
	fuzzKeys     []fuzzRSAKey
)

func fuzzMakeKey(bitsN, e int) fuzzRSAKey {
	E, one := big.NewInt(int64(e)), big.NewInt(1)
	for {
		p, _ := rand.Prime(rand.Reader, bitsN/2)
		q, _ := rand.Prime(rand.Reader, bitsN-bitsN/2)
		n := new(big.Int).Mul(p, q)
		phi := new(big.Int).Mul(new(big.Int).Sub(p, one), new(big.Int).Sub(q, one))
		d := new(big.Int).ModInverse(E, phi)
		if n.BitLen() == bitsN && d != nil {
			return fuzzRSAKey{pub: &rsa.PublicKey{N: n, E: e}, k: &rsaKey{N: n.Bytes(), E: e}, d: d, n: n}
		}
	}
}

func fuzzRSAKeys() []fuzzRSAKey {
	fuzzKeysOnce.Do(func() {
		for _, c := range [][2]int{{1024, 65537}, {1024, 3}, {1032, 65537}, {1023, 65537}, {2048, 3}, {2048, 65537}, {1536, 17}} {
			fuzzKeys = append(fuzzKeys, fuzzMakeKey(c[0], c[1]))
		}
	})
	return fuzzKeys
}

var fuzzHashes = []crypto.Hash{crypto.SHA256, crypto.SHA512, crypto.SHA384, crypto.SHA224, crypto.SHA1}

func cubeRootCeil(x *big.Int) *big.Int {
	r := new(big.Int).Lsh(big.NewInt(1), uint(x.BitLen()/3+2))
	for {
		r2 := new(big.Int).Mul(r, r)
		nr := new(big.Int).Div(x, r2)
		nr.Add(nr, new(big.Int).Lsh(r, 1))
		nr.Div(nr, big.NewInt(3))
		if nr.Cmp(r) >= 0 {
			break
		}
		r = nr
	}
	for new(big.Int).Exp(r, big.NewInt(3), nil).Cmp(x) < 0 {
		r.Add(r, big.NewInt(1))
	}
	return r
}

func rsaFuzzCase(key fuzzRSAKey, h, hs crypto.Hash, msg []byte, mode uint8, mut []byte) ([]byte, []byte) {
	hh := h.New()
	hh.Write(msg)
	digest := hh.Sum(nil)
	sh := hs.New()
	sh.Write(msg)
	sdig := sh.Sum(nil)
	size := (key.n.BitLen() + 7) / 8
	prefix := digestInfoPrefix[hs]
	em := make([]byte, size)
	em[1] = 1
	for i := 2; i < size-len(prefix)-len(sdig)-1; i++ {
		em[i] = 0xff
	}
	copy(em[size-len(prefix)-len(sdig):], prefix)
	copy(em[size-len(sdig):], sdig)
	sign := func(em []byte) []byte {
		return new(big.Int).Exp(new(big.Int).SetBytes(em), key.d, key.n).FillBytes(make([]byte, size))
	}
	switch mode % 7 {
	case 0:
		for i := 0; i+1 < len(mut); i += 2 {
			em[int(mut[i])*size/256] = mut[i+1]
		}
		return digest, sign(em)
	case 1:
		raw := make([]byte, size)
		copy(raw[max(0, size-len(mut)):], mut)
		return digest, sign(raw)
	case 2:
		sig := sign(em)
		for i, c := range mut {
			sig[i%size] ^= c
		}
		return digest, sig
	case 3:
		k := 0
		if len(mut) > 0 {
			k = int(mut[0])
		}
		var b []byte
		b = append(b, 0, 1)
		b = append(b, bytes.Repeat([]byte{0xff}, k)...)
		b = append(b, 0)
		b = append(b, prefix...)
		b = append(b, sdig...)
		if len(b) > size {
			b = b[:size]
		}
		g := mut
		if len(g) > 0 {
			g = g[1:]
		}
		for len(b) < size {
			if len(g) > 0 {
				b = append(b, g[0])
				g = g[1:]
			} else {
				b = append(b, 0)
			}
		}
		return digest, sign(b)
	case 4:
		var b []byte
		b = append(b, 0, 1)
		pad := 8
		if len(mut) > 0 {
			pad = int(mut[0]) % 64
		}
		b = append(b, bytes.Repeat([]byte{0xff}, pad)...)
		b = append(b, 0)
		b = append(b, prefix...)
		b = append(b, sdig...)
		if len(b) > size {
			b = b[:size]
		}
		for len(b) < size {
			b = append(b, 0xff)
		}
		r := cubeRootCeil(new(big.Int).SetBytes(b))
		if r.BitLen() > size*8 {
			return digest, sign(em)
		}
		return digest, r.FillBytes(make([]byte, size))
	case 5:
		sig := sign(em)
		if len(mut) > 0 && mut[0]&1 == 0 {
			return digest, append([]byte{0}, sig...)
		}
		return digest, sig[1:]
	default:
		v := new(big.Int).SetBytes(mut)
		switch {
		case len(mut) == 0:
			v = new(big.Int).Set(key.n)
		case mut[0]&3 == 0:
			v.Add(v, key.n)
		case mut[0]&3 == 1:
			v.Sub(key.n, big.NewInt(1))
		}
		if v.BitLen() > size*8 {
			return digest, mut
		}
		return digest, v.FillBytes(make([]byte, size))
	}
}

func FuzzRSAVerify(f *testing.F) {
	for m := range uint8(7) {
		for k := range uint8(7) {
			f.Add(k, uint8(0), uint8(0), []byte("Release"), m, []byte{})
		}
		f.Add(uint8(4), uint8(0), uint8(0), []byte("x"), m, []byte{0, 0x55, 255, 1, 128, 0})
		f.Add(uint8(1), uint8(1), uint8(1), []byte("InRelease"), m, []byte{8, 1, 2, 3})
	}
	f.Add(uint8(4), uint8(0), uint8(1), []byte("binding"), uint8(0), []byte{})
	f.Fuzz(func(t *testing.T, ki, hi, si uint8, msg []byte, mode uint8, mut []byte) {
		keys := fuzzRSAKeys()
		key := keys[int(ki)%len(keys)]
		h := fuzzHashes[int(hi)%len(fuzzHashes)]
		hs := h
		if si%4 == 1 {
			hs = fuzzHashes[int(si>>2)%len(fuzzHashes)]
		}
		digest, sig := rsaFuzzCase(key, h, hs, msg, mode, mut)
		got := rsaVerifyPKCS1v15(key.k, h, digest, sig)
		want := rsa.VerifyPKCS1v15(key.pub, h, digest, sig) == nil
		if got != want {
			t.Fatalf("key %d-bit e=%d hash %v sig-hash %v mode %d: custom %v, crypto/rsa %v\nsig %x", key.n.BitLen(), key.pub.E, h, hs, mode%7, got, want, sig)
		}
		if mode%7 == 0 && len(mut) < 2 && h == hs && key.n.BitLen() >= 1024 && !got {
			t.Fatalf("valid signature rejected (%d-bit e=%d %v)", key.n.BitLen(), key.pub.E, h)
		}
	})
}

func nonCanonical(n *big.Int, sig []byte, size int) []byte {
	v := new(big.Int).Add(n, new(big.Int).SetBytes(sig))
	if v.BitLen() > size*8 {
		v.Add(n, big.NewInt(1))
	}
	return v.FillBytes(make([]byte, size))
}

func TestRSAForgeryClasses(t *testing.T) {
	key := fuzzMakeKey(3072, 3)
	digest := sha256.Sum256([]byte("Release"))
	prefix := digestInfoPrefix[crypto.SHA256]
	size := 384
	build := func(pad int, tail []byte, fill byte) []byte {
		b := append([]byte{0, 1}, bytes.Repeat([]byte{0xff}, pad)...)
		b = append(b, 0)
		b = append(b, prefix...)
		b = append(b, digest[:]...)
		b = append(b, tail...)
		for len(b) < size {
			b = append(b, fill)
		}
		return b[:size]
	}
	forged := func(em []byte) []byte {
		return cubeRootCeil(new(big.Int).SetBytes(em)).FillBytes(make([]byte, size))
	}
	sign := func(em []byte) []byte {
		return new(big.Int).Exp(new(big.Int).SetBytes(em), key.d, key.n).FillBytes(make([]byte, size))
	}
	valid := sign(build(size-3-len(prefix)-len(digest), nil, 0))
	if !rsaVerifyPKCS1v15(key.k, crypto.SHA256, digest[:], valid) {
		t.Fatal("valid e=3 signature rejected")
	}
	cases := map[string][]byte{
		"bleichenbacher e=3 garbage after digest": forged(build(8, nil, 0xff)),
		"garbage after digest (signed)":           sign(build(8, nil, 0x41)),
		"short padding":                           sign(build(7, nil, 0)[:size]),
		"no padding":                              sign(append(append([]byte{0, 1, 0}, prefix...), append(digest[:], make([]byte, size-3-len(prefix)-len(digest))...)...)),
		"shorter signature":                       valid[1:],
		"leading zero prepended":                  append([]byte{0}, valid...),
		"signature = n":                           key.n.FillBytes(make([]byte, size)),
		"signature + n":                           nonCanonical(key.n, valid, size),
		"block type 2":                            sign(append([]byte{0, 2}, build(size-3-len(prefix)-len(digest), nil, 0)[2:]...)),
		"sha1 prefix with sha256 digest":          sign(append(append(append([]byte{0, 1}, bytes.Repeat([]byte{0xff}, size-3-len(digestInfoPrefix[crypto.SHA1])-32)...), append([]byte{0}, digestInfoPrefix[crypto.SHA1]...)...), digest[:]...)),
	}
	for name, sig := range cases {
		if rsaVerifyPKCS1v15(key.k, crypto.SHA256, digest[:], sig) {
			t.Errorf("%s accepted", name)
		}
		if rsa.VerifyPKCS1v15(key.pub, crypto.SHA256, digest[:], sig) == nil {
			t.Errorf("%s accepted by crypto/rsa too", name)
		}
	}
	small := fuzzMakeKey(768, 65537)
	if rsaVerifyPKCS1v15(small.k, crypto.SHA256, digest[:], sign(build(1, nil, 0))) {
		t.Error("768-bit key accepted")
	}
	for _, e := range []int{1, 2, 4, 65536, 1 << 31, -3} {
		k := &rsaKey{N: key.k.N, E: e}
		if rsaVerifyPKCS1v15(k, crypto.SHA256, digest[:], valid) {
			t.Errorf("exponent %d accepted", e)
		}
	}
	if k := newRSAKey(key.k.N, []byte{1, 0, 0, 0, 0, 3}); k.E != 0 {
		t.Errorf("oversized exponent parsed as %d", k.E)
	}
	if k := newRSAKey(key.k.N, []byte{0, 0, 1, 0, 1}); k.E != 65537 {
		t.Errorf("zero-padded exponent parsed as %d", k.E)
	}
	if rsaVerifyPKCS1v15(key.k, crypto.SHA256, digest[:31], valid) {
		t.Error("truncated digest accepted")
	}
}

func FuzzModExp(f *testing.F) {
	f.Add([]byte{0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff}, []byte{0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe}, uint64(65537))
	f.Add([]byte{1}, []byte{0}, uint64(3))
	f.Add([]byte{0x80, 0, 0, 0, 0, 0, 0, 0, 1}, []byte{0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff}, uint64(1<<63|1))
	f.Add(bytes.Repeat([]byte{0xff}, 512), bytes.Repeat([]byte{0xee}, 512), uint64(3))
	f.Fuzz(func(t *testing.T, mod, base []byte, e uint64) {
		if len(mod) > 600 || e == 0 {
			return
		}
		mod = trimZeros(mod)
		if len(mod) == 0 || mod[len(mod)-1]&1 == 0 {
			return
		}
		m := new(big.Int).SetBytes(mod)
		x := new(big.Int).Mod(new(big.Int).SetBytes(base), m)
		want := new(big.Int).Exp(x, new(big.Int).SetUint64(e), m).FillBytes(make([]byte, len(mod)))
		if got := modExp(x.FillBytes(make([]byte, len(mod))), e, mod); !bytes.Equal(got, want) {
			t.Fatalf("modExp(%x, %d, %x) = %x, want %x", x, e, m, got, want)
		}
	})
}

func FuzzDNSParse(f *testing.F) {
	q, _ := dnsQuery("deb.example.", 1)
	q[0], q[1] = 0x12, 0x34
	resp := append(append([]byte(nil), q...), 0xc0, 12, 0, 5, 0, 1, 0, 0, 0, 60, 0, 6, 3, 'c', 'd', 'n', 0xc0, 16, 3, 'c', 'd', 'n', 7, 'e', 'x', 'a', 'm', 'p', 'l', 'e', 0, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 192, 0, 2, 1)
	resp[2], resp[3], resp[7] = 0x81, 0x80, 2
	f.Add(resp, false)
	f.Add(q, true)
	loop := append(append([]byte(nil), q...), 0xc0, 0x30, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 1, 2, 3, 4)
	loop[2], loop[7] = 0x81, 1
	f.Add(loop, false)
	f.Fuzz(func(t *testing.T, msg []byte, v6 bool) {
		qt := uint16(1)
		if v6 {
			qt = 28
		}
		q, _ := dnsQuery("deb.example.", qt)
		q[0], q[1] = 0x12, 0x34
		if len(msg) >= 2 {
			msg[0], msg[1] = 0x12, 0x34
		}
		ips, _, ok := dnsParse(msg, q, "deb.example", qt)
		if ok && !dnsMatches(msg, q) {
			t.Fatal("accepted a response whose question does not match")
		}
		for _, a := range ips {
			if len(a.ip) != map[uint16]int{1: 4, 28: 16}[qt] {
				t.Fatalf("wrong address length %d", len(a.ip))
			}
		}
		for off := 0; off < len(msg) && off < 64; off++ {
			if n, end, ok := dnsName(msg, off); ok && (len(n) > 255 || end > len(msg) || end <= off) {
				t.Fatalf("name %q at %d: end %d", n, off, end)
			}
		}
	})
}

func xzRef(b []byte) ([]byte, error) {
	r, err := xz.NewReader(bytes.NewReader(b))
	if err != nil {
		return nil, err
	}
	var out bytes.Buffer
	_, err = io.CopyN(&out, r, 64<<20)
	if err == io.EOF {
		err = nil
	}
	return out.Bytes(), err
}

func FuzzXZDifferential(f *testing.F) {
	for _, x := range xzFixtures {
		if x.name != "slide" {
			f.Add(xzFixture(f, x.name))
		}
	}
	f.Fuzz(func(t *testing.T, b []byte) {
		got, err := xzDecode(bytes.NewReader(b))
		if err != nil {
			return
		}
		want, rerr := xzRef(b)
		if rerr != nil {
			if strings.Contains(rerr.Error(), "unsupported") || strings.Contains(rerr.Error(), "filter") || strings.Contains(rerr.Error(), "dictionary") {
				return
			}
			t.Fatalf("custom decoder accepted a stream ulikunitz/xz rejects (%v), %d bytes out", rerr, len(got))
		}
		if !bytes.Equal(got, want) {
			t.Fatalf("output differs: custom %d bytes, ulikunitz/xz %d bytes", len(got), len(want))
		}
	})
}

func FuzzXZRoundTrip(f *testing.F) {
	f.Add([]byte("hello hello hello kpkg"), uint8(0), uint16(0))
	f.Add(xzTestText(5000), uint8(1), uint16(300))
	f.Add(xzTestRand(3000), uint8(2), uint16(1000))
	f.Add(xzTestPat(70000), uint8(3), uint16(7))
	f.Fuzz(func(t *testing.T, data []byte, opt uint8, bs uint16) {
		checks := []byte{xz.CRC32, xz.CRC64, xz.SHA256, xz.None}
		cfg := xz.WriterConfig{CheckSum: checks[opt%4], DictCap: 4096 << (opt >> 2 % 8)}
		if bs > 0 {
			cfg.BlockSize = int64(bs) * 16
		}
		var buf bytes.Buffer
		w, err := cfg.NewWriter(&buf)
		if err != nil {
			return
		}
		w.Write(data)
		w.Close()
		enc := buf.Bytes()
		if opt&0x80 != 0 {
			enc = append(append(enc, 0, 0, 0, 0), enc...)
			data = append(append([]byte(nil), data...), data...)
		}
		got, err := xzDecode(bytes.NewReader(enc))
		if err != nil || !bytes.Equal(got, data) {
			t.Fatalf("round trip failed: %v (%d vs %d bytes)", err, len(got), len(data))
		}
		for _, cut := range []int{1, len(enc) / 2, len(enc) - 1} {
			if cut > 0 && cut < len(enc) {
				if _, err := xzDecode(bytes.NewReader(enc[:cut])); err == nil {
					t.Fatalf("truncated stream (%d of %d bytes) accepted", cut, len(enc))
				}
			}
		}
		if len(enc) > 40 {
			c := append([]byte(nil), enc...)
			c[len(c)-20] ^= 0x10
			if out, err := xzDecode(bytes.NewReader(c)); err == nil && !bytes.Equal(out, data) {
				t.Fatal("corrupted stream decoded to different data without an error")
			}
		}
	})
}

func TestXZAgainstXZUtils(t *testing.T) {
	bin, err := exec.LookPath("xz")
	if err != nil {
		t.Skip("xz not installed")
	}
	inputs := [][]byte{xzTestText(300000), xzTestRand(70000), xzTestPat(3 << 20), {}, []byte("x")}
	args := [][]string{{"-0"}, {"-6"}, {"-9", "-e"}, {"--check=crc32"}, {"--check=sha256"}, {"--check=none"}, {"--block-size=4096"}, {"--lzma2=preset=6,lc=4,lp=0,pb=0"}, {"--lzma2=lc=0,lp=4,pb=4"}, {"--lzma2=dict=4KiB,mf=hc3,mode=fast"}, {"-T2", "--block-size=65536"}}
	for _, in := range inputs {
		for _, a := range args {
			cmd := exec.Command(bin, append([]string{"-c"}, a...)...)
			cmd.Stdin = bytes.NewReader(in)
			enc, err := cmd.Output()
			if err != nil {
				t.Fatalf("xz %v: %v", a, err)
			}
			got, err := xzDecode(bytes.NewReader(enc))
			if err != nil || !bytes.Equal(got, in) {
				t.Fatalf("xz %v on %d bytes: %v", a, len(in), err)
			}
		}
	}
	dir := os.Getenv("KPKG_XZ_CORPUS")
	if dir == "" {
		return
	}
	files, _ := os.ReadDir(dir)
	for _, e := range files {
		if !strings.HasSuffix(e.Name(), ".xz") {
			continue
		}
		p := dir + "/" + e.Name()
		want, err := exec.Command(bin, "-dc", p).Output()
		if err != nil {
			t.Fatalf("%s: xz: %v", p, err)
		}
		fh, _ := os.Open(p)
		r, err := newXZReader(fh)
		if err != nil {
			t.Fatalf("%s: %v", p, err)
		}
		got, err := io.ReadAll(r)
		fh.Close()
		if err != nil || !bytes.Equal(got, want) {
			t.Fatalf("%s: %v (%d vs %d bytes)", p, err, len(got), len(want))
		}
		t.Logf("%s: %d bytes, sha256 %x", e.Name(), len(got), sha256.Sum256(got))
	}
}

func FuzzGzipRoundTrip(f *testing.F) {
	f.Add([]byte("hello hello hello"), []byte{3})
	f.Add(xzTestText(100000), []byte{0, 200, 17})
	f.Add(xzTestPat(1<<16), []byte{})
	f.Add(bytes.Repeat([]byte{0}, 40000), []byte{1, 2})
	f.Fuzz(func(t *testing.T, data, splits []byte) {
		if len(data) > 4<<20 {
			return
		}
		var buf bytes.Buffer
		w := newGzipWriter(&buf)
		rest := data
		for _, s := range splits {
			n := min(len(rest), int(s)*int(s))
			w.Write(rest[:n])
			rest = rest[n:]
		}
		w.Write(rest)
		if err := w.Close(); err != nil {
			t.Fatal(err)
		}
		r, err := gzip.NewReader(&buf)
		if err != nil {
			t.Fatal(err)
		}
		got, err := io.ReadAll(r)
		if err != nil || !bytes.Equal(got, data) {
			t.Fatalf("round trip: %v (%d vs %d bytes)", err, len(got), len(data))
		}
	})
}

func TestGzipWriterLarge(t *testing.T) {
	data := append(xzTestText(3<<20), xzTestRand(1<<20)...)
	data = append(data, xzTestPat(2<<20)...)
	var buf bytes.Buffer
	w := newGzipWriter(&buf)
	for len(data) > 0 {
		n := min(len(data), 70001)
		w.Write(data[:n])
		data = data[n:]
	}
	w.Close()
	r, err := gzip.NewReader(&buf)
	if err != nil {
		t.Fatal(err)
	}
	got, err := io.ReadAll(r)
	want := append(xzTestText(3<<20), xzTestRand(1<<20)...)
	want = append(want, xzTestPat(2<<20)...)
	if err != nil || !bytes.Equal(got, want) {
		t.Fatalf("large round trip: %v", err)
	}
}

func FuzzHostOf(f *testing.F) {
	for _, s := range []string{"http://deb.debian.org/debian", "https://user:pw@mirror.example:8080/x", "http://[2001:db8::1]:80/", "http://a@b@c/", "http://h?x=@evil/", "http://h#@evil/", "file:/srv/repo", "http://h\\@evil/", "mirror+http://deb.example/x"} {
		f.Add(s)
	}
	f.Fuzz(func(t *testing.T, s string) {
		got := hostOf(s)
		u, err := url.Parse(s)
		if err != nil || u.Scheme == "" || u.Host == "" || u.Opaque != "" || (!strings.HasPrefix(u.Host, "[") && strings.Trim(u.Hostname(), "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-") != "") {
			return
		}
		if want := u.Hostname(); got != want && !strings.Contains(u.Host, "%") {
			t.Fatalf("hostOf(%q) = %q, net/url says %q", s, got, want)
		}
	})
}

func FuzzParseRFC1123(f *testing.F) {
	for _, s := range []string{"Sat, 07 Dec 2024 08:15:02 UTC", "Mon, 02 Jan 2006 15:04:05 GMT", "Fri, 29 Feb 2008 10:00:00 GMT", "Fri, 30 Feb 2009 10:00:00 GMT", "Thu, 1 Feb 2029 00:00:00 UTC", "Sat, 07 Dec 2024 08:15:02 +0000"} {
		f.Add(s)
	}
	f.Fuzz(func(t *testing.T, s string) {
		got, ok := parseRFC1123(s)
		want, err := time.Parse(time.RFC1123, s)
		zone := s[strings.LastIndexByte(s, ' ')+1:]
		utc := zone == "UTC" || zone == "GMT"
		canonical := err == nil && utc && want.Year() > 0 && want.Format("Mon, 02 Jan 2006 15:04:05 ")+zone == s
		if canonical && (!ok || !got.Equal(want)) {
			t.Fatalf("%q: custom %v %v, time.Parse %v", s, got, ok, want)
		}
		if !ok {
			return
		}
		if got.Location() != time.UTC {
			t.Fatalf("%q: non-UTC result %v", s, got)
		}
		if err == nil && utc && !got.Equal(want) {
			t.Fatalf("%q: custom %v, time.Parse %v", s, got, want)
		}
		if err != nil && strings.Contains(err.Error(), "day out of range") {
			t.Fatalf("%q: accepted an impossible date as %v", s, got)
		}
	})
}

type oldPKIXPub struct {
	Algo      asn1.RawValue
	PublicKey asn1.BitString
}

type oldRSAPubASN struct {
	N *big.Int
	E int
}

func oldParseRSASPKI(der []byte) *rsaKey {
	var spki oldPKIXPub
	if _, err := asn1.Unmarshal(der, &spki); err != nil {
		return nil
	}
	var pub oldRSAPubASN
	if _, err := asn1.Unmarshal(spki.PublicKey.Bytes, &pub); err != nil {
		return nil
	}
	return &rsaKey{N: pub.N.Bytes(), E: pub.E}
}

func FuzzParseRSASPKI(f *testing.F) {
	for _, b := range []int{1024, 2048} {
		priv, _ := rsa.GenerateKey(rand.Reader, b)
		der, _ := x509.MarshalPKIXPublicKey(&priv.PublicKey)
		f.Add(der)
	}
	f.Fuzz(func(t *testing.T, der []byte) {
		k := parseRSASPKI(der)
		if k == nil {
			return
		}
		old := oldParseRSASPKI(der)
		if old == nil {
			if pk, err := x509.ParsePKIXPublicKey(der); err == nil {
				t.Fatalf("custom parser and x509 accept, previous parser rejects: %v", pk)
			}
			return
		}
		if !bytes.Equal(k.N, old.N) || (k.E != old.E && k.E != 0) {
			t.Fatalf("custom N=%x E=%d, previous N=%x E=%d", k.N, k.E, old.N, old.E)
		}
	})
}

func TestDNSSpoofAndGoParity(t *testing.T) {
	type behaviour func(q []byte) (resp []byte, spoof []byte)
	answer := func(q []byte, name string, recs ...[]byte) []byte {
		end := len(q)
		if _, o, ok := dnsName(q, 12); ok && len(q) > 12 {
			end = o + 4
		}
		r := append([]byte(nil), q[:end]...)
		r[2], r[3] = 0x81, 0x80
		binary.BigEndian.PutUint16(r[6:], uint16(len(recs)))
		binary.BigEndian.PutUint16(r[8:], 0)
		binary.BigEndian.PutUint16(r[10:], 0)
		for _, x := range recs {
			r = append(r, x...)
		}
		return r
	}
	rec := func(name string, typ uint16, data []byte) []byte {
		b := append(dnsNameBytes(name), byte(typ>>8), byte(typ), 0, 1, 0, 0, 0, 60, byte(len(data)>>8), byte(len(data)))
		return append(b, data...)
	}
	qname := func(q []byte) (string, uint16) {
		n, o, _ := dnsName(q, 12)
		return n, binary.BigEndian.Uint16(q[o:])
	}
	cases := []struct {
		name, host string
		fn         behaviour
		want       string
	}{
		{"plain", "a.test.", func(q []byte) ([]byte, []byte) {
			n, t := qname(q)
			if t != 1 {
				return answer(q, n), nil
			}
			return answer(q, n, rec(n, 1, []byte{192, 0, 2, 1})), nil
		}, "192.0.2.1"},
		{"cname chain", "a.test.", func(q []byte) ([]byte, []byte) {
			n, t := qname(q)
			if t != 1 {
				return answer(q, n), nil
			}
			return answer(q, n, rec(n, 5, dnsNameBytes("b.test.")), rec("b.test.", 5, dnsNameBytes("c.test.")), rec("c.test.", 1, []byte{192, 0, 2, 3})), nil
		}, "192.0.2.3"},
		{"out-of-chain answer ignored", "a.test.", func(q []byte) ([]byte, []byte) {
			n, t := qname(q)
			if t != 1 {
				return answer(q, n), nil
			}
			return answer(q, n, rec("evil.test.", 1, []byte{6, 6, 6, 6}), rec(n, 1, []byte{192, 0, 2, 4})), nil
		}, "192.0.2.4"},
		{"upper-case question echo", "a.test.", func(q []byte) ([]byte, []byte) {
			n, t := qname(q)
			r := answer(q, n)
			if t == 1 {
				r = answer(q, n, rec("A.TEST.", 1, []byte{192, 0, 2, 5}))
			}
			copy(r[12:], dnsNameBytes("A.TEST."))
			return r, nil
		}, "192.0.2.5"},
		{"spoof from another port first", "a.test.", func(q []byte) ([]byte, []byte) {
			n, t := qname(q)
			if t != 1 {
				return answer(q, n), nil
			}
			return answer(q, n, rec(n, 1, []byte{192, 0, 2, 6})), answer(q, n, rec(n, 1, []byte{6, 6, 6, 6}))
		}, "192.0.2.6"},
		{"wrong question", "a.test.", func(q []byte) ([]byte, []byte) {
			n, t := qname(q)
			if t != 1 {
				return answer(q, n), nil
			}
			r := answer(q, n, rec("b.test.", 1, []byte{6, 6, 6, 6}))
			copy(r[12:], dnsNameBytes("b.test."))
			return r, nil
		}, ""},
		{"no question section", "a.test.", func(q []byte) ([]byte, []byte) {
			n, _ := qname(q)
			r := answer(q[:12], n, rec(n, 1, []byte{6, 6, 6, 6}))
			r[5] = 0
			return r, nil
		}, ""},
		{"cname loop", "a.test.", func(q []byte) ([]byte, []byte) {
			n, _ := qname(q)
			return answer(q, n, rec(n, 5, dnsNameBytes("b.test.")), rec("b.test.", 5, dnsNameBytes(n))), nil
		}, ""},
		{"wrong class", "a.test.", func(q []byte) ([]byte, []byte) {
			n, t := qname(q)
			if t != 1 {
				return answer(q, n), nil
			}
			r := rec(n, 1, []byte{6, 6, 6, 6})
			r[len(dnsNameBytes(n))+3] = 3
			return answer(q, n, r), nil
		}, ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			pc, err := net.ListenPacket("udp4", "127.0.0.1:0")
			if err != nil {
				t.Fatal(err)
			}
			spoofer, _ := net.ListenPacket("udp4", "127.0.0.1:0")
			defer pc.Close()
			defer spoofer.Close()
			go func() {
				buf := make([]byte, 1500)
				for {
					n, a, err := pc.ReadFrom(buf)
					if err != nil {
						return
					}
					r, s := c.fn(append([]byte(nil), buf[:n]...))
					if s != nil {
						spoofer.WriteTo(s, a)
						time.Sleep(20 * time.Millisecond)
					}
					pc.WriteTo(r, a)
				}
			}()
			port := pc.LocalAddr().(*net.UDPAddr).Port
			withResolver(t, "nameserver 127.0.0.1\noptions timeout:1 attempts:1\n", "", port)
			ips, err := lookupHost(c.host)
			if got := ipStrings(ips); got != c.want {
				t.Errorf("custom resolver: %q %v, want %q", got, err, c.want)
			}
			res := &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
				var d net.Dialer
				return d.DialContext(ctx, network, pc.LocalAddr().String())
			}}
			ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
			defer cancel()
			gips, _ := res.LookupIP(ctx, "ip", c.host)
			var gs []string
			for _, ip := range gips {
				gs = append(gs, ip.String())
			}
			goWant := map[string]string{"out-of-chain answer ignored": "6.6.6.6,192.0.2.4", "wrong class": "6.6.6.6"}
			want, laxer := goWant[c.name]
			if !laxer {
				want = c.want
			}
			if got := strings.Join(gs, ","); got != want {
				t.Errorf("Go resolver: %q, want %q", got, want)
			}
		})
	}
}
