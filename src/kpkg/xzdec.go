package main

import (
	"bufio"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"hash"
	"hash/crc32"
	"io"
	"strconv"
	"sync"
)

var (
	errXZData  = errors.New("xz: corrupt data")
	errXZCheck = errors.New("xz: check mismatch")
)

const (
	oMatch = 0
	oRep   = 192
	oRep0  = 204
	oRep1  = 216
	oRep2  = 228
	oRep0L = 240
	oSlot  = 432
	oSpec  = 688
	oAlign = 802
	oML    = 818
	oRL    = 1332
	oLit   = 1846
	oEnd   = oLit + 0x300<<4
)

type xzReader struct {
	r                *bufio.Reader
	buf              []byte
	pos, rd, dict    int
	st, ns           int
	flags            [2]byte
	sh               hash.Hash
	csz              int
	c32              uint32
	c64              uint64
	recs             []uint64
	bh, bc, bu       uint64
	hc, hu           uint64
	needDict, needPr bool
	lc, lp, pb       uint
	s                int
	r0, r1, r2, r3   uint32
	ic               uint32
	isz              int
	err              error
	in               [1 << 16]byte
	p                [oEnd]uint16
}

func xzBit(r, c, i uint32, in *[1 << 16]byte, p *uint16) (uint32, uint32, uint32, int) {
	if r < 1<<24 {
		r <<= 8
		c = c<<8 | uint32(in[uint16(i)])
		i++
	}
	v := uint32(*p)
	b := (r >> 11) * v
	if c < b {
		*p = uint16(v + (2048-v)>>5)
		return b, c, i, 0
	}
	*p = uint16(v - v>>5)
	return r - b, c - b, i, 1
}

var (
	xzOnce sync.Once
	xzT64  [8][256]uint64
)

func xzTable() {
	for i := range 256 {
		c := uint64(i)
		for range 8 {
			c = c>>1 ^ 0xc96c5795d7870f42&-(c&1)
		}
		xzT64[0][i] = c
	}
	for k := 1; k < 8; k++ {
		for i := range 256 {
			c := xzT64[k-1][i]
			xzT64[k][i] = c>>8 ^ xzT64[0][byte(c)]
		}
	}
}

func xzCRC64(c uint64, p []byte) uint64 {
	t := &xzT64
	c = ^c
	for ; len(p) >= 8; p = p[8:] {
		c ^= binary.LittleEndian.Uint64(p)
		c = t[7][byte(c)] ^ t[6][byte(c>>8)] ^ t[5][byte(c>>16)] ^ t[4][byte(c>>24)] ^
			t[3][byte(c>>32)] ^ t[2][byte(c>>40)] ^ t[1][byte(c>>48)] ^ t[0][c>>56]
	}
	for _, b := range p {
		c = t[0][byte(c)^b] ^ c>>8
	}
	return ^c
}

func newXZReader(r io.Reader) (io.Reader, error) {
	br, ok := r.(*bufio.Reader)
	if !ok {
		br = bufio.NewReaderSize(r, 1<<16)
	}
	z := &xzReader{r: br}
	if err := z.header(); err != nil {
		return nil, err
	}
	return z, nil
}

func (z *xzReader) Read(p []byte) (int, error) {
	for z.rd == z.pos {
		if z.err != nil {
			return 0, z.err
		}
		switch z.st {
		case 0:
			z.err = z.header()
		case 1:
			z.err = z.block()
		default:
			z.err = z.chunk()
		}
	}
	n := copy(p, z.buf[z.rd:z.pos])
	z.rd += n
	return n, nil
}

func xzEOF(err error) error {
	if err == io.EOF {
		return io.ErrUnexpectedEOF
	}
	return err
}

func (z *xzReader) full(b []byte) error {
	_, err := io.ReadFull(z.r, b)
	return xzEOF(err)
}

func (z *xzReader) header() error {
	var h [12]byte
	for {
		n, err := io.ReadFull(z.r, h[:4])
		if z.ns > 0 && n == 0 && err == io.EOF {
			return io.EOF
		}
		if err != nil {
			return xzEOF(err)
		}
		if z.ns == 0 || binary.LittleEndian.Uint32(h[:]) != 0 {
			break
		}
	}
	if err := z.full(h[4:]); err != nil {
		return err
	}
	if string(h[:6]) != "\xfd7zXZ\x00" {
		return errors.New("xz: bad stream header")
	}
	if h[6] != 0 || h[7] > 15 || crc32.ChecksumIEEE(h[6:8]) != binary.LittleEndian.Uint32(h[8:]) {
		return errXZData
	}
	c := h[7]
	z.csz = 0
	if c != 0 {
		z.csz = 4 << ((c - 1) / 3)
	}
	if c != 0 && c != 1 && c != 4 && c != 10 {
		return errors.New("xz: unsupported check type " + strconv.Itoa(int(c)))
	}
	if c == 4 {
		xzOnce.Do(xzTable)
	}
	if c == 10 && z.sh == nil {
		z.sh = sha256.New()
	}
	z.flags = [2]byte{h[6], c}
	z.recs = z.recs[:0]
	z.st = 1
	z.ns++
	return nil
}

func xzVar(b []byte, i int) (uint64, int) {
	var v uint64
	for s := 0; s < 63; s += 7 {
		if i < 0 || i >= len(b) {
			return 0, -1
		}
		c := b[i]
		i++
		v |= uint64(c&0x7f) << s
		if c < 0x80 {
			if c == 0 && s > 0 {
				return 0, -1
			}
			return v, i
		}
	}
	return 0, -1
}

func (z *xzReader) block() error {
	h := z.in[:1024]
	c, err := z.r.ReadByte()
	if err != nil {
		return xzEOF(err)
	}
	if c == 0 {
		return z.index()
	}
	n := int(c)*4 + 4
	h[0] = c
	if err := z.full(h[1:n]); err != nil {
		return err
	}
	if crc32.ChecksumIEEE(h[:n-4]) != binary.LittleEndian.Uint32(h[n-4:]) {
		return errXZData
	}
	f, b := h[1], h[:n-4]
	if f&0x3c != 0 {
		return errors.New("xz: unsupported block flags")
	}
	i := 2
	z.hc, z.hu = 1<<63, 1<<63
	if f&0x40 != 0 {
		z.hc, i = xzVar(b, i)
	}
	if f&0x80 != 0 {
		z.hu, i = xzVar(b, i)
	}
	id, i := xzVar(b, i)
	if i > 0 && (f&3 != 0 || id != 0x21) {
		return errors.New("xz: unsupported filter 0x" + strconv.FormatUint(id, 16) + ", only LZMA2 is supported")
	}
	ps, i := xzVar(b, i)
	if i < 0 || ps != 1 || i >= len(b) || b[i] > 40 {
		return errXZData
	}
	d := b[i]
	if d > 37 {
		return errors.New("xz: dictionary too large")
	}
	for _, v := range b[i+1:] {
		if v != 0 {
			return errXZData
		}
	}
	z.dict = (2 | int(d&1)) << (d/2 + 11)
	z.bh, z.bc, z.bu = uint64(n), 0, 0
	z.needDict, z.needPr = true, true
	z.c32, z.c64 = 0, 0
	if z.csz == 32 {
		z.sh.Reset()
	}
	z.st = 2
	return nil
}

func (z *xzReader) ib() (byte, error) {
	c, err := z.r.ReadByte()
	if err != nil {
		return 0, xzEOF(err)
	}
	z.ic = crc32.Update(z.ic, crc32.IEEETable, []byte{c})
	z.isz++
	return c, nil
}

func (z *xzReader) ivar() (uint64, error) {
	var v uint64
	for s := 0; s < 63; s += 7 {
		c, err := z.ib()
		if err != nil {
			return 0, err
		}
		v |= uint64(c&0x7f) << s
		if c < 0x80 {
			if c == 0 && s > 0 {
				break
			}
			return v, nil
		}
	}
	return 0, errXZData
}

func (z *xzReader) index() error {
	z.ic, z.isz = crc32.ChecksumIEEE([]byte{0}), 1
	n, err := z.ivar()
	if err != nil {
		return err
	}
	if n != uint64(len(z.recs)/2) {
		return errXZData
	}
	for _, r := range z.recs {
		v, err := z.ivar()
		if err != nil {
			return err
		}
		if v != r {
			return errXZData
		}
	}
	for z.isz&3 != 0 {
		c, err := z.ib()
		if err != nil {
			return err
		}
		if c != 0 {
			return errXZData
		}
	}
	var t [16]byte
	if err := z.full(t[:]); err != nil {
		return err
	}
	if binary.LittleEndian.Uint32(t[:]) != z.ic || binary.LittleEndian.Uint32(t[4:]) != crc32.ChecksumIEEE(t[8:14]) ||
		(int(binary.LittleEndian.Uint32(t[8:]))+1)*4 != z.isz+4 || t[12] != z.flags[0] || t[13] != z.flags[1] || t[14] != 'Y' || t[15] != 'Z' {
		return errXZData
	}
	z.st = 0
	return nil
}

func (z *xzReader) endBlock() error {
	if z.hc < 1<<63 && z.hc != z.bc || z.hu < 1<<63 && z.hu != z.bu {
		return errXZData
	}
	var t [32]byte
	k := -int(z.bh+z.bc) & 3
	if err := z.full(t[:k]); err != nil {
		return err
	}
	if binary.LittleEndian.Uint32(t[:]) != 0 {
		return errXZData
	}
	var s [32]byte
	switch z.csz {
	case 4:
		binary.LittleEndian.PutUint32(s[:], z.c32)
	case 8:
		binary.LittleEndian.PutUint64(s[:], z.c64)
	case 32:
		z.sh.Sum(s[:0])
	}
	if err := z.full(t[:z.csz]); err != nil {
		return err
	}
	if t != s {
		return errXZCheck
	}
	z.recs = append(z.recs, z.bh+z.bc+uint64(z.csz), z.bu)
	z.st = 1
	return nil
}

func (z *xzReader) room(u int) {
	m := z.dict + z.dict>>2 + 3<<20
	if z.pos+u > m {
		sh := (z.pos - min(z.pos, z.dict)) &^ 15
		copy(z.buf, z.buf[sh:z.pos])
		z.pos -= sh
		z.rd = z.pos
	}
	if z.pos+u > len(z.buf) {
		b := make([]byte, min(max(2*len(z.buf), z.pos+u, 1<<16), max(m, z.pos+u)))
		copy(b, z.buf[:z.pos])
		z.buf = b
	}
}

func (z *xzReader) out(u int) error {
	p := z.buf[z.pos : z.pos+u]
	switch z.csz {
	case 4:
		z.c32 = crc32.Update(z.c32, crc32.IEEETable, p)
	case 8:
		z.c64 = xzCRC64(z.c64, p)
	case 32:
		z.sh.Write(p)
	}
	z.pos += u
	z.bu += uint64(u)
	return nil
}

func (z *xzReader) chunk() error {
	var s [5]byte
	c, err := z.r.ReadByte()
	if err != nil {
		return xzEOF(err)
	}
	z.bc++
	if c == 0 {
		return z.endBlock()
	}
	if c >= 0xe0 || c == 1 {
		z.needPr, z.needDict = true, false
		z.pos, z.rd = 0, 0
	} else if z.needDict {
		return errXZData
	}
	if c < 0x80 {
		if c > 2 {
			return errXZData
		}
		if err := z.full(s[:2]); err != nil {
			return err
		}
		u := int(s[0])<<8 | int(s[1]) + 1
		z.room(u)
		if err := z.full(z.buf[z.pos : z.pos+u]); err != nil {
			return err
		}
		z.bc += 2 + uint64(u)
		return z.out(u)
	}
	k := 4
	if c >= 0xc0 {
		k = 5
	}
	if err := z.full(s[:k]); err != nil {
		return err
	}
	u := int(c&0x1f)<<16 | int(s[0])<<8 | int(s[1]) + 1
	cs := int(s[2])<<8 | int(s[3]) + 1
	if c >= 0xc0 {
		p := uint(s[4])
		if p >= 225 {
			return errXZData
		}
		z.lc, z.lp, z.pb = p%9, p/9%5, p/45
		if z.lc+z.lp > 4 {
			return errXZData
		}
		z.needPr = false
	} else if z.needPr {
		return errXZData
	}
	if c >= 0xa0 {
		z.s, z.r0, z.r1, z.r2, z.r3 = 0, 0, 0, 0, 0
		for i := range z.p[:oLit+0x300<<(z.lc+z.lp)] {
			z.p[i] = 1024
		}
	}
	if cs < 5 {
		return errXZData
	}
	if err := z.full(z.in[:cs]); err != nil {
		return err
	}
	z.bc += uint64(k + cs)
	z.room(u)
	if err := z.lzma(u, cs); err != nil {
		return err
	}
	return z.out(u)
}

func (z *xzReader) lzma(u, cs int) error {
	in, pr, b := &z.in, &z.p, z.buf
	if in[0] != 0 {
		return errXZData
	}
	rg, cd, ip := uint32(0xffffffff), uint32(in[1])<<24|uint32(in[2])<<16|uint32(in[3])<<8|uint32(in[4]), uint32(5)
	pos, end, dict := z.pos, z.pos+u, z.dict
	st, r0, r1, r2, r3 := z.s, z.r0, z.r1, z.r2, z.r3
	lc, lpm, pbm := z.lc, 1<<z.lp-1, 1<<z.pb-1
	var bt int
	for pos < end {
		ps := pos & pbm
		rg, cd, ip, bt = xzBit(rg, cd, ip, in, &pr[oMatch+st<<4+ps])
		if bt == 0 {
			prev := 0
			if pos > 0 {
				prev = int(b[pos-1])
			}
			k := oLit + 0x300*((pos&lpm)<<lc+prev>>(8-lc))
			t := (*[0x300]uint16)(pr[k : k+0x300])
			sym := 1
			if st < 7 {
				for sym < 0x100 {
					rg, cd, ip, bt = xzBit(rg, cd, ip, in, &t[sym])
					sym = sym<<1 | bt
				}
			} else {
				mb := int(b[pos-int(r0)-1])
				off := 0x100
				for sym < 0x100 {
					mb <<= 1
					m := mb & off
					rg, cd, ip, bt = xzBit(rg, cd, ip, in, &t[off+m+sym])
					sym = sym<<1 | bt
					if bt == 0 {
						off ^= m
					} else {
						off = m
					}
				}
			}
			b[pos] = byte(sym)
			pos++
			if st < 4 {
				st = 0
			} else if st < 10 {
				st -= 3
			} else {
				st -= 6
			}
			continue
		}
		lb := oRL
		rg, cd, ip, bt = xzBit(rg, cd, ip, in, &pr[oRep+st])
		if bt == 0 {
			r3, r2, r1 = r2, r1, r0
			lb = oML
		} else {
			rg, cd, ip, bt = xzBit(rg, cd, ip, in, &pr[oRep0+st])
			if bt == 0 {
				rg, cd, ip, bt = xzBit(rg, cd, ip, in, &pr[oRep0L+st<<4+ps])
				if bt == 0 {
					if uint(r0) >= uint(pos) || uint(r0) >= uint(dict) {
						return errXZData
					}
					st = 9 + st/7*2
					b[pos] = b[pos-int(r0)-1]
					pos++
					continue
				}
			} else {
				rg, cd, ip, bt = xzBit(rg, cd, ip, in, &pr[oRep1+st])
				t := r1
				if bt != 0 {
					rg, cd, ip, bt = xzBit(rg, cd, ip, in, &pr[oRep2+st])
					t = r2
					if bt != 0 {
						t, r3 = r3, r2
					}
					r2 = r1
				}
				r1, r0 = r0, t
			}
		}
		var tb, lim, l int
		rg, cd, ip, bt = xzBit(rg, cd, ip, in, &pr[lb])
		if bt == 0 {
			tb, lim, l = lb+2+ps<<3, 8, 2
		} else {
			rg, cd, ip, bt = xzBit(rg, cd, ip, in, &pr[lb+1])
			if bt == 0 {
				tb, lim, l = lb+130+ps<<3, 8, 10
			} else {
				tb, lim, l = lb+258, 256, 18
			}
		}
		sym := 1
		for sym < lim {
			rg, cd, ip, bt = xzBit(rg, cd, ip, in, &pr[tb+sym])
			sym = sym<<1 | bt
		}
		l += sym - lim
		if lb == oML {
			st = 7 + st/7*3
			tb = oSlot + min(l-2, 3)<<6
			sym = 1
			for sym < 64 {
				rg, cd, ip, bt = xzBit(rg, cd, ip, in, &pr[tb+sym])
				sym = sym<<1 | bt
			}
			sl := uint32(sym - 64)
			r0 = sl
			if sl >= 4 {
				nb := sl>>1 - 1
				r0 = 2 | sl&1
				if sl < 14 {
					r0 <<= nb
					tb = oSpec + int(r0) - int(sl) - 1
				} else {
					for k := nb - 4; k > 0; k-- {
						if rg < 1<<24 {
							rg <<= 8
							cd = cd<<8 | uint32(in[uint16(ip)])
							ip++
						}
						rg >>= 1
						r0 <<= 1
						if cd >= rg {
							cd -= rg
							r0++
						}
					}
					r0 <<= 4
					tb, nb = oAlign, 4
				}
				sym = 1
				for k := range nb {
					rg, cd, ip, bt = xzBit(rg, cd, ip, in, &pr[tb+sym])
					sym = sym<<1 | bt
					r0 += uint32(bt) << k
				}
			}
		} else {
			st = 8 + st/7*3
		}
		if uint(r0) >= uint(pos) || uint(r0) >= uint(dict) || l > end-pos {
			return errXZData
		}
		src := pos - int(r0) - 1
		if r0 >= 7 && pos+l+8 <= len(b) {
			for i := 0; i < l; i += 8 {
				binary.LittleEndian.PutUint64(b[pos+i:], binary.LittleEndian.Uint64(b[src+i:]))
			}
		} else if int(r0) >= l {
			copy(b[pos:pos+l], b[src:src+l])
		} else {
			w := b[src : pos+l]
			for i := range l {
				w[i+int(r0)+1] = w[i]
			}
		}
		pos += l
	}
	if rg < 1<<24 {
		cd = cd<<8 | uint32(in[uint16(ip)])
		ip++
	}
	z.s, z.r0, z.r1, z.r2, z.r3 = st, r0, r1, r2, r3
	if cd != 0 || ip != uint32(cs) {
		return errXZData
	}
	return nil
}
