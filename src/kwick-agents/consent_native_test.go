package main

import "testing"

func TestConsentAnswer(t *testing.T) {
	cases := map[string]string{
		"qml: kwick-consent:once":  "once",
		"kwick-consent:always":     "always",
		"js: kwick-consent:deny":   "deny",
		"kwick-consent:everything": "",
		"qml: something else":      "",
		"kwick-consent: once ":     "once",
	}
	for in, want := range cases {
		if got := consentAnswer(in); got != want {
			t.Fatalf("%q: got %q want %q", in, got, want)
		}
	}
	for _, app := range []string{"qml6", "org.qt-project.qml"} {
		if protectedReason(winInfo{App: app, Title: consentTitle}) == "" {
			t.Fatalf("the consent dialog from %s is not protected", app)
		}
	}
	for c := range capVerbs {
		if _, ok := capByName(c); !ok {
			t.Fatalf("unknown capability %s", c)
		}
	}
	for _, c := range capabilities {
		if capVerbs[c.Name] == "" {
			t.Fatalf("no verb for %s", c.Name)
		}
	}
}
