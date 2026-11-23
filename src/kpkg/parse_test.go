package main

import (
	"reflect"
	"strings"
	"testing"
	"time"
)

func parseAll(data string, keep map[string]bool) []*Paragraph {
	var out []*Paragraph
	ParseParagraphs(strings.NewReader(data), keep, func(p *Paragraph) error { out = append(out, p); return nil })
	return out
}

func TestParseParagraphsEdgeCases(t *testing.T) {
	cases := []struct {
		name string
		in   string
		keep map[string]bool
		want []map[string]string
	}{
		{"crlf", "Package: a\r\nDescription: x\r\n more\r\n\r\nPackage: b\r\n", nil,
			[]map[string]string{{"Package": "a", "Description": "x\n more"}, {"Package": "b"}}},
		{"empty-first-line", "Package: a\nDescription:\n line1\n .\n line2\n\n\n\nPackage: b\nX:  y  \n z\n", nil,
			[]map[string]string{{"Package": "a", "Description": "\n line1\n .\n line2"}, {"Package": "b", "X": "y\n z"}}},
		{"comments", "# c\nPackage: a\n# mid\nDepends: b\n cont\n", nil,
			[]map[string]string{{"Package": "a", "Depends": "b\n cont"}}},
		{"tabs", "Package:\ta\t\nD: v\n\tt\n   \n\t\nPackage: c", nil,
			[]map[string]string{{"Package": "a", "D": "v\n\tt"}, {"Package": "c"}}},
		{"keep", "Package: a\nTag: x\n y\nVersion: 1\n", map[string]bool{"Package": true, "Version": true},
			[]map[string]string{{"Package": "a", "Version": "1"}}},
		{"duplicate", "A: 1\nA: 2\n x\n", nil,
			[]map[string]string{{"A": "2\n x"}}},
	}
	for _, c := range cases {
		got := parseAll(c.in, c.keep)
		if len(got) != len(c.want) {
			t.Fatalf("%s: got %d paragraphs, want %d", c.name, len(got), len(c.want))
		}
		for i := range got {
			if !reflect.DeepEqual(got[i].M, c.want[i]) {
				t.Fatalf("%s: paragraph %d = %q, want %q", c.name, i, got[i].M, c.want[i])
			}
		}
	}
}

func TestSplitParagraphChunks(t *testing.T) {
	var b strings.Builder
	for i := 0; i < 40000; i++ {
		b.WriteString("Package: p\nVersion: 1\nDescription: d\n more text here\n\n")
	}
	s := b.String()
	chunks := splitParagraphChunks(s, 8)
	if len(chunks) < 2 || strings.Join(chunks, "") != s {
		t.Fatalf("bad split: %d chunks", len(chunks))
	}
	n := 0
	for _, c := range chunks {
		parseParagraphString(c, nil, func(p *Paragraph) error {
			if p.Get("Description") != "d\n more text here" {
				t.Fatalf("bad paragraph %q", p.M)
			}
			n++
			return nil
		})
	}
	if n != 40000 {
		t.Fatalf("got %d paragraphs", n)
	}
}

func TestParseRFC1123(t *testing.T) {
	for _, s := range []string{"Sat, 07 Dec 2024 08:15:02 UTC", "Mon, 02 Jan 2006 15:04:05 GMT", "Tue, 31 Dec 2030 23:59:59 UTC", "Fri, 29 Feb 2008 10:00:00 GMT"} {
		want, err := time.Parse(time.RFC1123, strings.Replace(s, "UTC", "GMT", 1))
		got, ok := parseRFC1123(s)
		if err != nil || !ok || got.Unix() != want.Unix() {
			t.Errorf("%q: got %v %v, want %v %v", s, got, ok, want, err)
		}
	}
	if got, ok := parseRFC1123("Thu, 1 Feb 2029 00:00:00 UTC"); !ok || !got.Equal(time.Date(2029, 2, 1, 0, 0, 0, 0, time.UTC)) {
		t.Errorf("single-digit day: %v %v", got, ok)
	}
	for _, s := range []string{"", "Sat, 07 Dec 2024 08:15 UTC", "Sat 07 Dec 2024 08:15:02 UTC", "Sat, 07 Dex 2024 08:15:02 UTC", "Sat, 07 Dec 2024 25:15:02 UTC", "Sat, 07 Dec 2024 08:15:02 +0000", "Sat, 32 Dec 2024 08:15:02 UTC"} {
		if _, ok := parseRFC1123(s); ok {
			t.Errorf("%q accepted", s)
		}
	}
}
