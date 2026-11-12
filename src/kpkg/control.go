package main

import (
	"bufio"
	"io"
	"strings"
)

// Paragraph is an ordered deb822 stanza.
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

// ParseParagraphs streams deb822 stanzas to fn. keep (optional) filters
// which fields are stored, which keeps memory low for huge indexes.
func ParseParagraphs(r io.Reader, keep map[string]bool, fn func(*Paragraph) error) error {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 1<<20), 16<<20)
	p := NewParagraph()
	last := ""
	flush := func() error {
		if len(p.Keys) == 0 {
			return nil
		}
		err := fn(p)
		p = NewParagraph()
		last = ""
		return err
	}
	for sc.Scan() {
		line := sc.Text()
		if strings.HasSuffix(line, "\r") {
			line = line[:len(line)-1]
		}
		if strings.TrimSpace(line) == "" {
			if err := flush(); err != nil {
				return err
			}
			continue
		}
		if line[0] == ' ' || line[0] == '\t' {
			if last != "" {
				p.M[last] += "\n" + line
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
			continue
		}
		p.Set(k, strings.TrimSpace(line[i+1:]))
		last = k
	}
	if err := sc.Err(); err != nil {
		return err
	}
	return flush()
}
