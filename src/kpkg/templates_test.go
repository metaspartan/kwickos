package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const tzTemplates = `Template: tzdata/Areas
Type: select
Choices-C: Africa, America, Etc
Choices: Africa, America, Etc
Choices-de.UTF-8: Afrika, Amerika, Etc
Choices-en_GB.UTF-8: Africa, America, Etc
Default: Etc
Description: Geographic area:
 Please select the geographic area in which you live.
 .
 Subsequent configuration questions will narrow this down.
Description-de.UTF-8: Geografisches Gebiet:
 Bitte waehlen Sie das geografische Gebiet.
 .
 Nachfolgende Fragen grenzen dies ein.
Description-pt_BR.UTF-8: Area geografica:
 Por favor, selecione a area.
Description-en_GB.UTF-8: Geographic area:
 Please select the area.

Template: tzdata/Zones/Etc
Type: select
Choices: UTC
Description-fr.UTF-8: Fuseau horaire :
Description: Time zone:
`

const tzTrimmed = `Template: tzdata/Areas
Type: select
Choices-C: Africa, America, Etc
Choices: Africa, America, Etc
Choices-en_GB.UTF-8: Africa, America, Etc
Default: Etc
Description: Geographic area:
 Please select the geographic area in which you live.
 .
 Subsequent configuration questions will narrow this down.
Description-en_GB.UTF-8: Geographic area:
 Please select the area.

Template: tzdata/Zones/Etc
Type: select
Choices: UTC
Description: Time zone:
`

func TestTrimTemplatesFollowsLocaleExcludes(t *testing.T) {
	f := &pathFilter{rules: []filterRule{
		{false, "/usr/share/locale/*"},
		{true, "/usr/share/locale/en*"},
	}}
	if got := string(trimTemplates([]byte(tzTemplates), f)); got != tzTrimmed {
		t.Fatalf("trimmed templates:\n%s\nwant:\n%s", got, tzTrimmed)
	}
}

func TestTrimTemplatesKeepsEverythingWithoutLocaleExcludes(t *testing.T) {
	for _, f := range []*pathFilter{nil, {rules: []filterRule{{false, "/usr/share/doc/*"}}}} {
		if got := string(trimTemplates([]byte(tzTemplates), f)); got != tzTemplates {
			t.Fatalf("templates changed with filter %v:\n%s", f, got)
		}
	}
}

func TestTrimTemplatesKeepsIncludedLanguage(t *testing.T) {
	f := &pathFilter{rules: []filterRule{
		{false, "/usr/share/locale/*"},
		{true, "/usr/share/locale/de/*"},
	}}
	got := string(trimTemplates([]byte(tzTemplates), f))
	for _, want := range []string{"Description-de.UTF-8: Geografisches Gebiet:\n Bitte", "Choices-de.UTF-8: Afrika", "Choices-C: Africa"} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}
	for _, gone := range []string{"pt_BR", "fr.UTF-8", "en_GB"} {
		if strings.Contains(got, gone) {
			t.Errorf("%q survived in:\n%s", gone, got)
		}
	}
}

func TestTemplateLang(t *testing.T) {
	cases := []struct {
		field, lang string
		ok          bool
	}{
		{"Description-de.UTF-8", "de", true},
		{"description-pt_BR.UTF-8", "pt_BR", true},
		{"Choices-sr@latin.UTF-8", "sr@latin", true},
		{"Choices-C", "", false},
		{"Choices", "", false},
		{"Description", "", false},
		{"Default-de", "", false},
		{"Extended_description-de.UTF-8", "", false},
	}
	for _, c := range cases {
		lang, ok := templateLang(c.field)
		if lang != c.lang || ok != c.ok {
			t.Errorf("templateLang(%q) = %q, %v; want %q, %v", c.field, lang, ok, c.lang, c.ok)
		}
	}
}

func TestUnpackTrimsTemplateTranslations(t *testing.T) {
	setupMA(t)
	d := filepath.Join(cfg.Root, "etc/dpkg/dpkg.cfg.d")
	os.MkdirAll(d, 0755)
	os.MkdirAll(infoDir(), 0755)
	os.WriteFile(filepath.Join(d, "excludes"), []byte("path-exclude=/usr/share/locale/*\npath-include=/usr/share/locale/en*\n"), 0644)
	src := filepath.Join(t.TempDir(), "src")
	os.MkdirAll(filepath.Join(src, "DEBIAN"), 0755)
	os.MkdirAll(filepath.Join(src, "usr/share/zoneinfo"), 0755)
	os.WriteFile(filepath.Join(src, "DEBIAN/control"), []byte("Package: tzdata\nVersion: 1.0\nArchitecture: all\n"), 0644)
	os.WriteFile(filepath.Join(src, "DEBIAN/templates"), []byte(tzTemplates), 0644)
	os.WriteFile(filepath.Join(src, "usr/share/zoneinfo/UTC"), []byte("TZif"), 0644)
	deb := filepath.Join(t.TempDir(), "tzdata.deb")
	if err := buildDeb(src, deb); err != nil {
		t.Fatal(err)
	}
	tx := testTx()
	tx.loadOwners()
	if err := tx.unpack(&Pkg{Name: "tzdata", Version: "1.0", Arch: "all"}, deb); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(filepath.Join(infoDir(), "tzdata.templates"))
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != tzTrimmed {
		t.Fatalf("installed templates:\n%s\nwant:\n%s", got, tzTrimmed)
	}
}
