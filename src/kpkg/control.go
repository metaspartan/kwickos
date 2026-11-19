package main

import (
	"io"
	"strings"
	"unsafe"
)

type Paragraph struct {
	Keys []string
	M    map[string]string
}

func NewParagraph() *Paragraph { return &Paragraph{M: map[string]string{}} }

func (p *Paragraph) Get(k string) string { return p.M[k] }

func (p *Paragraph) Set(k, v string) {
	if _, ok := p.M[k]; !ok {
		p.Keys = append(p.Keys, k)
	}
	p.M[k] = v
}

func (p *Paragraph) Del(k string) {
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
	last := ""
	lastEnd := -1
	flush := func() error {
		if len(p.Keys) == 0 {
			return nil
		}
		err := fn(p)
		p = newParagraphSized()
		last = ""
		lastEnd = -1
		return err
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
		if line[0] == ' ' || line[0] == '\t' {
			if last != "" {
				cur := p.M[last]
				if lastEnd >= 0 && lineStart == lastEnd+1 {
					p.M[last] = s[lastEnd-len(cur) : lineEnd]
					lastEnd = lineEnd
				} else {
					p.M[last] = cur + "\n" + line
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
		k := line[:i]
		if keep != nil && !keep[k] {
			last = ""
			lastEnd = -1
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
		p.Set(k, line[a:e])
		last = k
		if e == len(line) {
			lastEnd = lineEnd
		} else {
			lastEnd = -1
		}
	}
	return flush()
}
