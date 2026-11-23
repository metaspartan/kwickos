package main

import (
	"archive/tar"
	"bytes"
	"strings"
)

func templateLang(field string) (string, bool) {
	for _, base := range []string{"Description-", "Choices-"} {
		if len(field) > len(base) && strings.EqualFold(field[:len(base)], base) {
			lang, _, _ := strings.Cut(field[len(base):], ".")
			if lang == "" || strings.EqualFold(lang, "C") {
				return "", false
			}
			return lang, true
		}
	}
	return "", false
}

func (f *pathFilter) dropsLang(lang string) bool {
	if f == nil || strings.ContainsAny(lang, "/*?[\\") {
		return false
	}
	return f.skip("/usr/share/locale/"+lang+"/LC_MESSAGES/debconf.mo", tar.TypeReg)
}

func trimTemplates(b []byte, f *pathFilter) []byte {
	if f == nil {
		return b
	}
	var out bytes.Buffer
	out.Grow(len(b))
	drop := false
	for len(b) > 0 {
		line := b
		if i := bytes.IndexByte(b, '\n'); i >= 0 {
			line, b = b[:i+1], b[i+1:]
		} else {
			b = nil
		}
		if len(line) > 0 && (line[0] == ' ' || line[0] == '\t') {
			if !drop {
				out.Write(line)
			}
			continue
		}
		drop = false
		if i := bytes.IndexByte(line, ':'); i > 0 {
			if lang, ok := templateLang(string(line[:i])); ok && f.dropsLang(lang) {
				drop = true
				continue
			}
		}
		out.Write(line)
	}
	return out.Bytes()
}
