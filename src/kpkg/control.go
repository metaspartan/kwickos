package main

import (
	"io"
	"strings"
	"sync"
	"unsafe"
)

type Paragraph struct {
	Keys []string
	M    map[string]string
	raw  string
	lazy bool
	once sync.Once
}

func NewParagraph() *Paragraph { return &Paragraph{M: map[string]string{}} }

func lazyParagraph(raw string) *Paragraph { return &Paragraph{raw: raw, lazy: true} }

func (p *Paragraph) ensure() {
	if p.lazy {
		p.once.Do(p.expand)
	}
}

func (p *Paragraph) expand() {
	p.Keys = make([]string, 0, 16)
	p.M = make(map[string]string, 16)
	scanParagraphs(p.raw, nil, p.set, nil)
}

func (p *Paragraph) Fields() []string {
	p.ensure()
	return p.Keys
}

func (p *Paragraph) Get(k string) string {
	p.ensure()
	return p.M[k]
}

func (p *Paragraph) Set(k, v string) {
	p.ensure()
	p.set(k, v)
}

func (p *Paragraph) set(k, v string) {
	if _, ok := p.M[k]; !ok {
		p.Keys = append(p.Keys, k)
	}
	p.M[k] = v
}

func (p *Paragraph) Del(k string) {
	p.ensure()
	if _, ok := p.M[k]; !ok {
		return
	}
	delete(p.M, k)
	for i, x := range p.Keys {
		if x == k {
			p.Keys = append(p.Keys[:i], p.Keys[i+1:]...)
			break
		}
	}
}

func (p *Paragraph) Write822(w io.Writer) {
	p.ensure()
	var b strings.Builder
	for _, k := range p.Keys {
		v := p.M[k]
		b.WriteString(k)
		b.WriteString(":")
		if v != "" && v[0] != '\n' {
			b.WriteString(" ")
		}
		b.WriteString(v)
		b.WriteString("\n")
	}
	io.WriteString(w, b.String())
}

func newParagraphSized() *Paragraph {
	return &Paragraph{Keys: make([]string, 0, 16), M: make(map[string]string, 16)}
}

func ParseParagraphs(r io.Reader, keep map[string]bool, fn func(*Paragraph) error) error {
	var s string
	if sr, ok := r.(*strings.Reader); ok && sr.Len() == int(sr.Size()) {
		var b strings.Builder
		b.Grow(sr.Len())
		io.Copy(&b, sr)
		s = b.String()
	} else {
		b, err := io.ReadAll(r)
		if err != nil {
			return err
		}
		if len(b) > 0 {
			s = unsafe.String(unsafe.SliceData(b), len(b))
		}
	}
	return parseParagraphString(s, keep, fn)
}

func blankLine(l string) bool {
	for i := 0; i < len(l); i++ {
		switch l[i] {
		case ' ', '\t', '\r', '\v', '\f':
		default:
			return false
		}
	}
	return true
}

func parseParagraphString(s string, keep map[string]bool, fn func(*Paragraph) error) error {
	p := newParagraphSized()
	return scanParagraphs(s, keep, func(k, v string) { p.set(k, v) }, func(int, int) error {
		err := fn(p)
		p = newParagraphSized()
		return err
	})
}

func scanParagraphs(s string, keep map[string]bool, field func(k, v string), end func(start, stop int) error) error {
	key, val, have := "", "", false
	lastEnd := -1
	start, stop, n := -1, 0, 0
	emit := func() {
		if have {
			field(key, val)
			n++
		}
		key, val, have = "", "", false
		lastEnd = -1
	}
	flush := func() error {
		emit()
		cnt := n
		a, b := start, stop
		start, n = -1, 0
		if cnt == 0 || end == nil {
			return nil
		}
		return end(a, b)
	}
	pos := 0
	for pos < len(s) {
		lineStart := pos
		lineEnd := len(s)
		if nl := strings.IndexByte(s[pos:], '\n'); nl >= 0 {
			lineEnd = pos + nl
			pos = lineEnd + 1
		} else {
			pos = len(s)
		}
		rawEnd := lineEnd
		if lineEnd > lineStart && s[lineEnd-1] == '\r' {
			lineEnd--
		}
		line := s[lineStart:lineEnd]
		if blankLine(line) {
			if err := flush(); err != nil {
				return err
			}
			continue
		}
		if start < 0 {
			start = lineStart
		}
		stop = rawEnd
		if line[0] == ' ' || line[0] == '\t' {
			if have && key != "" {
				if lastEnd >= 0 && lineStart == lastEnd+1 {
					val = s[lastEnd-len(val) : lineEnd]
					lastEnd = lineEnd
				} else {
					val = val + "\n" + line
					lastEnd = -1
				}
			}
			continue
		}
		if line[0] == '#' {
			continue
		}
		i := strings.IndexByte(line, ':')
		if i < 0 {
			continue
		}
		emit()
		k := line[:i]
		if keep != nil && !keep[k] {
			continue
		}
		a := i + 1
		for a < len(line) && (line[a] == ' ' || line[a] == '\t') {
			a++
		}
		e := len(line)
		for e > a && (line[e-1] == ' ' || line[e-1] == '\t' || line[e-1] == '\v' || line[e-1] == '\f') {
			e--
		}
		key, val, have = k, line[a:e], true
		if e == len(line) {
			lastEnd = lineEnd
		} else {
			lastEnd = -1
		}
	}
	return flush()
}
