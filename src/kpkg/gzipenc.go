package main

import (
	"encoding/binary"
	"hash/crc32"
	"io"
	"math/bits"
)

const (
	gzWin   = 32768
	gzBlock = 1 << 20
)

var (
	gzLenBase  = [29]uint16{3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258}
	gzLenExtra = [29]uint8{0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0}
)

type gzWriter struct {
	w     io.Writer
	buf   []byte
	done  int
	base  int
	head  []int
	crc   uint32
	size  uint32
	out   []byte
	bits  uint64
	nbits uint
	err   error
}

func newGzipWriter(w io.Writer) *gzWriter {
	z := &gzWriter{w: w, head: make([]int, 1<<16)}
	for i := range z.head {
		z.head[i] = -1 << 40
	}
	z.out = append(z.out, 0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff)
	return z
}

func (z *gzWriter) put(v uint64, n uint) {
	z.bits |= v << z.nbits
	z.nbits += n
	for z.nbits >= 8 {
		z.out = append(z.out, byte(z.bits))
		z.bits >>= 8
		z.nbits -= 8
	}
}

func (z *gzWriter) code(c uint32, n uint) {
	z.put(uint64(bits.Reverse32(c)>>(32-n)), n)
}

func (z *gzWriter) sym(s int) {
	switch {
	case s < 144:
		z.code(0x30+uint32(s), 8)
	case s < 256:
		z.code(0x190+uint32(s-144), 9)
	case s < 280:
		z.code(uint32(s-256), 7)
	default:
		z.code(0xc0+uint32(s-280), 8)
	}
}

func (z *gzWriter) match(l, d int) {
	i := 28
	if l < 258 {
		i = 0
		for i < 27 && int(gzLenBase[i+1]) <= l {
			i++
		}
	}
	z.sym(257 + i)
	z.put(uint64(l-int(gzLenBase[i])), uint(gzLenExtra[i]))
	d--
	if d < 4 {
		z.code(uint32(d), 5)
		return
	}
	nb := uint(bits.Len(uint(d))) - 2
	z.code(uint32(2*nb+uint(d>>nb&1)+2), 5)
	z.put(uint64(d&(1<<nb-1)), nb)
}

func gzHash(b []byte) uint32 {
	return binary.LittleEndian.Uint32(b) * 0x9E3779B1 >> 16
}

func (z *gzWriter) block(final bool) {
	fb := uint64(2)
	if final {
		fb = 3
	}
	z.put(fb, 3)
	b, end := z.buf, len(z.buf)
	for i := z.done; i < end; {
		if i+4 <= end {
			h := gzHash(b[i:])
			c := z.head[h] - z.base
			z.head[h] = i + z.base
			if c >= 0 && i-c <= gzWin && binary.LittleEndian.Uint32(b[c:]) == binary.LittleEndian.Uint32(b[i:]) {
				l := 4
				for l < 258 && i+l < end && b[c+l] == b[i+l] {
					l++
				}
				z.match(l, i-c)
				for j := i + 1; j < i+l && j+4 <= end; j++ {
					z.head[gzHash(b[j:])] = j + z.base
				}
				i += l
				continue
			}
		}
		z.sym(int(b[i]))
		i++
	}
	z.sym(256)
	z.done = end
	if shift := end - gzWin; shift > 0 {
		z.buf = z.buf[:copy(z.buf, z.buf[shift:])]
		z.base += shift
		z.done -= shift
	}
	z.flush()
}

func (z *gzWriter) flush() {
	if z.err == nil && len(z.out) > 0 {
		_, z.err = z.w.Write(z.out)
	}
	z.out = z.out[:0]
}

func (z *gzWriter) Write(p []byte) (int, error) {
	if z.err != nil {
		return 0, z.err
	}
	z.crc = crc32.Update(z.crc, crc32.IEEETable, p)
	z.size += uint32(len(p))
	n := len(p)
	for len(p) > 0 {
		k := min(len(p), z.done+gzBlock-len(z.buf))
		z.buf = append(z.buf, p[:k]...)
		p = p[k:]
		if len(z.buf)-z.done >= gzBlock {
			z.block(false)
		}
	}
	return n, z.err
}

func (z *gzWriter) Close() error {
	z.block(true)
	if z.nbits > 0 {
		z.put(0, 8-z.nbits)
	}
	z.out = binary.LittleEndian.AppendUint32(z.out, z.crc)
	z.out = binary.LittleEndian.AppendUint32(z.out, z.size)
	z.flush()
	return z.err
}
