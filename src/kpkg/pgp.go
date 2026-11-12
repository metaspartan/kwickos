package main

// Minimal OpenPGP verification: exactly what is needed to check Debian
// style clearsigned InRelease files against a keyring. Supports v4 keys
// and signatures with RSA and Ed25519 (legacy EdDSA and RFC 9580 algo 27).
// No external dependencies, so kpkg stays small and auditable.

import (
	"bytes"
	"crypto"
	"crypto/ed25519"
	"crypto/sha1"
	_ "crypto/sha256"
	_ "crypto/sha512"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"math/big"
	"os"
	"strings"
)

type rsaKey struct {
	N *big.Int
	E int
}

type pgpKey struct {
	id  uint64
	rsa *rsaKey
	ed  ed25519.PublicKey
}

// DER DigestInfo prefixes for EMSA-PKCS1-v1_5 (RFC 8017, section 9.2).
var digestInfoPrefix = map[crypto.Hash][]byte{
	crypto.SHA224: {0x30, 0x2d, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x04, 0x05, 0x00, 0x04, 0x1c},
	crypto.SHA256: {0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20},
	crypto.SHA384: {0x30, 0x41, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02, 0x05, 0x00, 0x04, 0x30},
	crypto.SHA512: {0x30, 0x51, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03, 0x05, 0x00, 0x04, 0x40},
}

// rsaVerifyPKCS1v15 checks an RSASSA-PKCS1-v1_5 signature. Verification
// only touches public data, so a plain math/big implementation is fine and
// avoids linking Go's FIPS RSA module (~0.5 MB).
func rsaVerifyPKCS1v15(k *rsaKey, h crypto.Hash, digest, sig []byte) bool {
	size := (k.N.BitLen() + 7) / 8
	prefix, ok := digestInfoPrefix[h]
	if !ok || len(sig) != size || k.E < 3 {
		return false
	}
	s := new(big.Int).SetBytes(sig)
	if s.Cmp(k.N) >= 0 {
		return false
	}
	em := new(big.Int).Exp(s, big.NewInt(int64(k.E)), k.N).FillBytes(make([]byte, size))
	tLen := len(prefix) + len(digest)
	if size < tLen+11 || em[0] != 0 || em[1] != 1 || em[size-tLen-1] != 0 {
		return false
	}
	for _, b := range em[2 : size-tLen-1] {
		if b != 0xff {
			return false
		}
	}
	return bytes.Equal(em[size-tLen:size-len(digest)], prefix) && bytes.Equal(em[size-len(digest):], digest)
}

type Keyring map[uint64]*pgpKey

type pkt struct {
	tag  int
	body []byte
}

var errPGP = errors.New("malformed OpenPGP data")

func readPackets(b []byte) (out []pkt, err error) {
	defer func() {
		if recover() != nil {
			err = errPGP
		}
	}()
	for len(b) > 0 {
		h := b[0]
		b = b[1:]
		if h&0x80 == 0 {
			return nil, errPGP
		}
		var tag, l int
		if h&0x40 != 0 {
			tag = int(h & 0x3f)
			c := int(b[0])
			switch {
			case c < 192:
				l, b = c, b[1:]
			case c < 224:
				l, b = (c-192)<<8+int(b[1])+192, b[2:]
			case c == 255:
				l, b = int(binary.BigEndian.Uint32(b[1:5])), b[5:]
			default:
				return nil, errors.New("partial-length packets unsupported")
			}
		} else {
			tag = int(h>>2) & 0xf
			switch h & 3 {
			case 0:
				l, b = int(b[0]), b[1:]
			case 1:
				l, b = int(binary.BigEndian.Uint16(b)), b[2:]
			case 2:
				l, b = int(binary.BigEndian.Uint32(b)), b[4:]
			default:
				l = len(b)
			}
		}
		if l > len(b) {
			return nil, errPGP
		}
		out = append(out, pkt{tag, b[:l]})
		b = b[l:]
	}
	return out, nil
}

func readMPI(b []byte) ([]byte, []byte) {
	bits := int(binary.BigEndian.Uint16(b))
	n := (bits + 7) / 8
	return b[2 : 2+n], b[2+n:]
}

var oidEd25519 = []byte{0x2B, 0x06, 0x01, 0x04, 0x01, 0xDA, 0x47, 0x0F, 0x01}

func parseKey(body []byte) (k *pgpKey) {
	defer func() {
		if recover() != nil {
			k = nil
		}
	}()
	if body[0] != 4 {
		return nil
	}
	algo := body[5]
	p := body[6:]
	k = &pgpKey{}
	switch algo {
	case 1, 2, 3:
		n, rest := readMPI(p)
		e, _ := readMPI(rest)
		k.rsa = &rsaKey{N: new(big.Int).SetBytes(n), E: int(new(big.Int).SetBytes(e).Int64())}
	case 22:
		ol := int(p[0])
		if !bytes.Equal(p[1:1+ol], oidEd25519) {
			return nil
		}
		pt, _ := readMPI(p[1+ol:])
		if len(pt) != 33 || pt[0] != 0x40 {
			return nil
		}
		k.ed = ed25519.PublicKey(pt[1:])
	case 27:
		k.ed = ed25519.PublicKey(p[:32])
	default:
		return nil
	}
	h := sha1.New()
	h.Write([]byte{0x99, byte(len(body) >> 8), byte(len(body))})
	h.Write(body)
	fp := h.Sum(nil)
	k.id = binary.BigEndian.Uint64(fp[12:20])
	return k
}

func dearmor(data []byte) [][]byte {
	var blocks [][]byte
	lines := strings.Split(strings.ReplaceAll(string(data), "\r", ""), "\n")
	for i := 0; i < len(lines); i++ {
		if !strings.HasPrefix(lines[i], "-----BEGIN PGP") {
			continue
		}
		i++
		for i < len(lines) && strings.TrimSpace(lines[i]) != "" && strings.Contains(lines[i], ":") {
			i++
		}
		var b64 strings.Builder
		for ; i < len(lines) && !strings.HasPrefix(lines[i], "-----END PGP"); i++ {
			l := strings.TrimSpace(lines[i])
			if l == "" || strings.HasPrefix(l, "=") {
				continue
			}
			b64.WriteString(l)
		}
		if raw, err := base64.StdEncoding.DecodeString(b64.String()); err == nil {
			blocks = append(blocks, raw)
		}
	}
	return blocks
}

// LoadKeyring loads binary or ASCII-armored keyrings.
func (kr Keyring) Load(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	blocks := [][]byte{data}
	if bytes.Contains(data, []byte("-----BEGIN PGP")) {
		blocks = dearmor(data)
	}
	for _, b := range blocks {
		pk, err := readPackets(b)
		if err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
		for _, p := range pk {
			if p.tag == 6 || p.tag == 14 {
				if k := parseKey(p.body); k != nil {
					kr[k.id] = k
				}
			}
		}
	}
	return nil
}

var hashAlgos = map[byte]crypto.Hash{8: crypto.SHA256, 9: crypto.SHA384, 10: crypto.SHA512, 11: crypto.SHA224}

func subpackets(b []byte, fn func(typ byte, data []byte)) {
	defer func() { recover() }()
	for len(b) > 0 {
		l := int(b[0])
		switch {
		case l < 192:
			b = b[1:]
		case l < 255:
			l = (l-192)<<8 + int(b[1]) + 192
			b = b[2:]
		default:
			l = int(binary.BigEndian.Uint32(b[1:5]))
			b = b[5:]
		}
		if l == 0 || l > len(b) {
			return
		}
		fn(b[0]&0x7f, b[1:l])
		b = b[l:]
	}
}

func verifySig(body, signed []byte, kr Keyring) (ok bool, err error) {
	defer func() {
		if recover() != nil {
			ok, err = false, errPGP
		}
	}()
	if body[0] != 4 {
		return false, errors.New("unsupported signature version")
	}
	pkAlgo, hAlgo := body[2], body[3]
	hl := int(binary.BigEndian.Uint16(body[4:6]))
	hashed := body[6 : 6+hl]
	hashedPart := body[:6+hl]
	rest := body[6+hl:]
	ul := int(binary.BigEndian.Uint16(rest))
	unhashed := rest[2 : 2+ul]
	rest = rest[2+ul:]
	left16 := rest[:2]
	sigData := rest[2:]
	var issuer uint64
	find := func(t byte, d []byte) {
		switch {
		case t == 16 && len(d) == 8:
			issuer = binary.BigEndian.Uint64(d)
		case t == 33 && len(d) == 21 && d[0] == 4:
			issuer = binary.BigEndian.Uint64(d[13:21])
		}
	}
	subpackets(hashed, find)
	if issuer == 0 {
		subpackets(unhashed, find)
	}
	key := kr[issuer]
	if key == nil {
		return false, fmt.Errorf("NO_PUBKEY %016X", issuer)
	}
	hh, ok2 := hashAlgos[hAlgo]
	if !ok2 {
		return false, fmt.Errorf("unsupported hash algorithm %d", hAlgo)
	}
	h := hh.New()
	h.Write(signed)
	h.Write(hashedPart)
	var tr [6]byte
	tr[0], tr[1] = 4, 0xff
	binary.BigEndian.PutUint32(tr[2:], uint32(len(hashedPart)))
	h.Write(tr[:])
	digest := h.Sum(nil)
	if digest[0] != left16[0] || digest[1] != left16[1] {
		return false, errors.New("BADSIG (digest prefix mismatch)")
	}
	switch {
	case (pkAlgo == 1 || pkAlgo == 3) && key.rsa != nil:
		s, _ := readMPI(sigData)
		kl := (key.rsa.N.BitLen() + 7) / 8
		if len(s) < kl {
			s = append(make([]byte, kl-len(s)), s...)
		}
		if !rsaVerifyPKCS1v15(key.rsa, hh, digest, s) {
			return false, errors.New("BADSIG")
		}
		return true, nil
	case pkAlgo == 22 && key.ed != nil:
		r, rest := readMPI(sigData)
		s, _ := readMPI(rest)
		sig := make([]byte, 64)
		copy(sig[32-len(r):32], r)
		copy(sig[64-len(s):], s)
		return ed25519.Verify(key.ed, digest, sig), nil
	case pkAlgo == 27 && key.ed != nil:
		return ed25519.Verify(key.ed, digest, sigData[:64]), nil
	}
	return false, fmt.Errorf("unsupported key algorithm %d", pkAlgo)
}

// VerifyClearsigned checks a clearsigned message and returns its text.
func VerifyClearsigned(data []byte, kr Keyring) (string, error) {
	s := strings.ReplaceAll(string(data), "\r\n", "\n")
	const begin = "-----BEGIN PGP SIGNED MESSAGE-----\n"
	if !strings.HasPrefix(s, begin) {
		return "", errors.New("not a clearsigned message")
	}
	s = s[len(begin):]
	hdrEnd := strings.Index(s, "\n\n")
	if hdrEnd < 0 {
		return "", errPGP
	}
	s = s[hdrEnd+2:]
	sigStart := strings.Index(s, "\n-----BEGIN PGP SIGNATURE-----")
	if sigStart < 0 {
		return "", errors.New("missing signature block")
	}
	msg := s[:sigStart]
	sigArmor := s[sigStart+1:]
	lines := strings.Split(msg, "\n")
	canon := make([]string, len(lines))
	for i, l := range lines {
		if strings.HasPrefix(l, "- ") {
			l = l[2:]
		}
		lines[i] = l
		canon[i] = strings.TrimRight(l, " \t")
	}
	signed := []byte(strings.Join(canon, "\r\n"))
	text := strings.Join(lines, "\n") + "\n"
	var lastErr error = errors.New("no valid signature")
	for _, blk := range dearmor([]byte(sigArmor)) {
		pk, err := readPackets(blk)
		if err != nil {
			return "", err
		}
		for _, p := range pk {
			if p.tag != 2 {
				continue
			}
			ok, err := verifySig(p.body, signed, kr)
			if ok {
				return text, nil
			}
			if err != nil {
				lastErr = err
			}
		}
	}
	return "", lastErr
}
