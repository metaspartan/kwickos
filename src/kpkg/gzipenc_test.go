package main

import (
	"bytes"
	stdgzip "compress/gzip"
	"io"
	"math/rand"
	"strings"
	"testing"

	"github.com/klauspost/compress/gzip"
)

func gzRoundTrip(t *testing.T, data []byte, chunk int) int {
	var buf bytes.Buffer
	zw := newGzipWriter(&buf)
	for p := data; len(p) > 0; {
		n := min(chunk, len(p))
		if _, err := zw.Write(p[:n]); err != nil {
			t.Fatal(err)
		}
		p = p[n:]
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	for _, open := range []func(io.Reader) (io.Reader, error){
		func(r io.Reader) (io.Reader, error) { return stdgzip.NewReader(r) },
		func(r io.Reader) (io.Reader, error) { return gzip.NewReader(r) },
	} {
		zr, err := open(bytes.NewReader(buf.Bytes()))
		if err != nil {
			t.Fatal(err)
		}
		got, err := io.ReadAll(zr)
		if err != nil {
			t.Fatalf("len %d chunk %d: %v", len(data), chunk, err)
		}
		if !bytes.Equal(got, data) {
			t.Fatalf("len %d chunk %d: round trip mismatch", len(data), chunk)
		}
	}
	return buf.Len()
}

func TestGzipWriter(t *testing.T) {
	r := rand.New(rand.NewSource(1))
	random := make([]byte, 3<<20)
	r.Read(random)
	var text strings.Builder
	for text.Len() < 5<<20 {
		text.WriteString("Package: libfoo")
		text.WriteString(string(rune('a' + r.Intn(26))))
		text.WriteString("\nVersion: 1.2.")
		text.WriteString(strings.Repeat("9", r.Intn(4)))
		text.WriteString("\nDescription: a library that does things\n\n")
	}
	skewed := make([]byte, 2<<20)
	for i := range skewed {
		skewed[i] = byte(r.ExpFloat64() * 8)
	}
	cases := [][]byte{nil, {0}, []byte("abc"), []byte("abcd"), []byte(strings.Repeat("a", 1000)), make([]byte, 3<<20), random, []byte(text.String()), skewed}
	for _, c := range cases {
		for _, chunk := range []int{1 << 30, 4096, 777} {
			if len(c) > 1<<20 && chunk == 777 {
				continue
			}
			gzRoundTrip(t, c, chunk)
		}
	}
	if n := gzRoundTrip(t, []byte(text.String()), 1<<16); n > text.Len()/5 {
		t.Fatalf("text compressed poorly: %d of %d", n, text.Len())
	}
}
