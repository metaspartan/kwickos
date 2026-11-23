package main

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
)

type fmtItem struct {
	lit   string
	field string
	width int
	isFld bool
}

func parseShowFormat(f string) ([]fmtItem, error) {
	if f == "" {
		return nil, errors.New("may not be empty string")
	}
	var items []fmtItem
	var lit strings.Builder
	flush := func() {
		if lit.Len() > 0 {
			items = append(items, fmtItem{lit: lit.String()})
			lit.Reset()
		}
	}
	for i := 0; i < len(f); {
		c := f[i]
		switch {
		case c == '\\':
			i++
			if i >= len(f) {
				break
			}
			switch f[i] {
			case 'n':
				lit.WriteByte('\n')
			case 't':
				lit.WriteByte('\t')
			case 'r':
				lit.WriteByte('\r')
			case 'v':
				lit.WriteByte('\v')
			case 'f':
				lit.WriteByte('\f')
			default:
				lit.WriteByte(f[i])
			}
			i++
		case c == '$' && i+1 < len(f) && f[i+1] == '{':
			j := strings.IndexByte(f[i:], '}')
			if j < 0 {
				return nil, errors.New("missing closing brace")
			}
			body := f[i+2 : i+j]
			i += j + 1
			name, w, hasW := strings.Cut(body, ";")
			it := fmtItem{field: name, isFld: true}
			if hasW {
				if w == "-" {
					return nil, errors.New("invalid character '-' in field width")
				}
				for k := 0; k < len(w); k++ {
					if !(w[k] >= '0' && w[k] <= '9') && !(k == 0 && w[k] == '-') {
						return nil, fmt.Errorf("invalid character '%c' in field width", w[k])
					}
				}
				it.width, _ = strconv.Atoi(w)
			}
			flush()
			items = append(items, it)
		default:
			lit.WriteByte(c)
			i++
		}
	}
	flush()
	return items, nil
}

func statusParts(st string) (string, string, string) {
	f := strings.Fields(st)
	for len(f) < 3 {
		f = append(f, "")
	}
	return f[0], f[1], f[2]
}

func lookupField(in *Installed, name string) string {
	if v := in.Field(name); v != "" {
		return v
	}
	for _, k := range in.P.Fields() {
		if strings.EqualFold(k, name) {
			return in.P.Get(k)
		}
	}
	return ""
}

func sourceVersion(in *Installed) string {
	src := in.Field("Source")
	if i := strings.IndexByte(src, '('); i >= 0 {
		if j := strings.IndexByte(src[i:], ')'); j > 0 {
			return strings.TrimSpace(src[i+1 : i+j])
		}
	}
	return in.Version
}

func upstreamVersion(v string) string {
	if i := strings.IndexByte(v, ':'); i >= 0 {
		v = v[i+1:]
	}
	if i := strings.LastIndexByte(v, '-'); i >= 0 {
		v = v[:i]
	}
	return v
}

func fieldValue(in *Installed, field string) string {
	want, eflag, status := statusParts(in.Status)
	switch strings.ToLower(field) {
	case "binary:package":
		return in.InfoName()
	case "package":
		return in.Name
	case "db:status-abbrev":
		return statusAbbrev(in.Status)
	case "db:status-want":
		return want
	case "db:status-eflag":
		return eflag
	case "db:status-status":
		return status
	case "status":
		return in.Status
	case "source:package":
		return strings.Fields(in.Field("Source") + " " + in.Name)[0]
	case "source:version":
		return sourceVersion(in)
	case "source:upstream-version":
		return upstreamVersion(sourceVersion(in))
	case "binary:synopsis", "binary:summary":
		return strings.SplitN(in.Field("Description"), "\n", 2)[0]
	}
	v := lookupField(in, field)
	if v == "" && strings.EqualFold(field, "Essential") {
		return "no"
	}
	return v
}

func padField(v string, width int) string {
	switch {
	case width > 0:
		if len(v) > width {
			v = v[:width]
		}
		return fmt.Sprintf("%*s", width, v)
	case width < 0:
		if len(v) > -width {
			v = v[:-width]
		}
		return fmt.Sprintf("%-*s", -width, v)
	}
	return v
}

func expandFormat(items []fmtItem, in *Installed) string {
	var b strings.Builder
	for _, it := range items {
		if !it.isFld {
			b.WriteString(it.lit)
			continue
		}
		b.WriteString(padField(fieldValue(in, it.field), it.width))
	}
	return b.String()
}
