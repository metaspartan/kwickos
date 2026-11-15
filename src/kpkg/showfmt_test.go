package main

import "testing"

func fmtInstalled() *Installed {
	p := mkPkg("Package: samba-common", "Version: 2:4.22.11+dfsg-0+deb13u1", "Architecture: all", "Multi-Arch: foreign",
		"Installed-Size: 124", "Source: samba (2:4.22.11+dfsg-0+deb13u1)", "Description: common files\n used by both")
	return &Installed{Pkg: p, Status: "install ok installed"}
}

func TestShowFormat(t *testing.T) {
	in := fmtInstalled()
	cases := []struct {
		f, want string
	}{
		{"${Status}", "install ok installed"},
		{"${Package}", "samba-common"},
		{"${binary:Package}", "samba-common"},
		{"${Version}", "2:4.22.11+dfsg-0+deb13u1"},
		{"${db:Status-Abbrev}", "ii "},
		{"${db:Status-Want}|${db:Status-Eflag}|${db:Status-Status}", "install|ok|installed"},
		{"${Package;-20}|", "samba-common        |"},
		{"${Package;20}|", "        samba-common|"},
		{"${Version;10}", "2:4.22.11+"},
		{"${Version;-10}", "2:4.22.11+"},
		{"${Package;3}", "sam"},
		{"a\\nb\\tc\\\\d\\\"e", "a\nb\tc\\d\"e"},
		{"\\q\\a\\x41", "qax41"},
		{"x\\", "x"},
		{"\\\\${Package}", "\\samba-common"},
		{"${Missing}|", "|"},
		{"${}|", "|"},
		{"${Essential}", "no"},
		{"${Package;}", "samba-common"},
		{"${Installed-Size}", "124"},
		{"${package}", "samba-common"},
		{"${binary:Synopsis}", "common files"},
		{"${source:Version}|${source:Upstream-Version}|${source:Package}", "2:4.22.11+dfsg-0+deb13u1|4.22.11+dfsg|samba"},
		{"${Architecture}/${Multi-Arch}", "all/foreign"},
		{"$notafield ${", ""},
		{"price: $5\\n", "price: $5\n"},
	}
	for _, c := range cases {
		items, err := parseShowFormat(c.f)
		if c.f == "$notafield ${" {
			if err == nil {
				t.Errorf("%q: expected error", c.f)
			}
			continue
		}
		if err != nil {
			t.Errorf("%q: %v", c.f, err)
			continue
		}
		if got := expandFormat(items, in); got != c.want {
			t.Errorf("%q => %q want %q", c.f, got, c.want)
		}
	}
}

func TestShowFormatErrors(t *testing.T) {
	for _, f := range []string{"", "${Package", "${Package;x}", "${Package;1x}", "${Package;-}"} {
		if _, err := parseShowFormat(f); err == nil {
			t.Errorf("%q: expected error", f)
		}
	}
}

func TestStatusAbbrev(t *testing.T) {
	cases := map[string]string{
		"install ok installed":             "ii ",
		"deinstall ok config-files":        "rc ",
		"purge ok not-installed":           "pn ",
		"install ok unpacked":              "iU ",
		"install reinstreq half-installed": "iHR",
		"hold ok installed":                "hi ",
		"install ok triggers-pending":      "it ",
		"unknown ok not-installed":         "un ",
	}
	for st, want := range cases {
		if got := statusAbbrev(st); got != want {
			t.Errorf("%q => %q want %q", st, got, want)
		}
	}
}

func TestDpkgQueryShortFormatOption(t *testing.T) {
	for _, args := range [][]string{
		{"-W", "-f=${Status}", "pkg"}, {"-W", "-f${Status}", "pkg"}, {"-W", "--showformat=${Status}", "pkg"},
		{"-W", "-f", "${Status}", "pkg"}, {"-f=${Status}", "-W", "pkg"}, {"--show", "--showformat", "${Status}", "pkg"},
	} {
		cmd, format, pats := parseQueryArgs(args)
		if format != "${Status}" {
			t.Errorf("%v: format %q", args, format)
		}
		if cmd != "-W" && cmd != "--show" {
			t.Errorf("%v: cmd %q", args, cmd)
		}
		if len(pats) != 1 || pats[0] != "pkg" {
			t.Errorf("%v: pats %v", args, pats)
		}
	}
}
