package main

import (
	"fmt"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

type keyDef struct {
	sym  uint32
	name string
	mod  bool
}

type keyCombo struct {
	mods []keyDef
	key  keyDef
}

var modKeys = map[string]keyDef{
	"ctrl": {0xffe3, "ctrl", true}, "control": {0xffe3, "ctrl", true},
	"shift": {0xffe1, "shift", true},
	"alt":   {0xffe9, "alt", true}, "option": {0xffe9, "alt", true},
	"super": {0xffeb, "logo", true}, "meta": {0xffeb, "logo", true}, "win": {0xffeb, "logo", true}, "cmd": {0xffeb, "logo", true}, "logo": {0xffeb, "logo", true},
	"altgr": {0xfe03, "altgr", true},
}

var namedKeys = map[string]keyDef{
	"enter": {0xff0d, "Return", false}, "return": {0xff0d, "Return", false},
	"escape": {0xff1b, "Escape", false}, "esc": {0xff1b, "Escape", false},
	"tab": {0xff09, "Tab", false}, "backspace": {0xff08, "BackSpace", false},
	"delete": {0xffff, "Delete", false}, "del": {0xffff, "Delete", false}, "insert": {0xff63, "Insert", false},
	"home": {0xff50, "Home", false}, "end": {0xff57, "End", false},
	"pageup": {0xff55, "Prior", false}, "page_up": {0xff55, "Prior", false}, "pagedown": {0xff56, "Next", false}, "page_down": {0xff56, "Next", false},
	"left": {0xff51, "Left", false}, "up": {0xff52, "Up", false}, "right": {0xff53, "Right", false}, "down": {0xff54, "Down", false},
	"space": {0x20, "space", false}, "print": {0xff61, "Print", false}, "menu": {0xff67, "Menu", false}, "capslock": {0xffe5, "Caps_Lock", false},
	"volumeup": {0x1008ff13, "XF86AudioRaiseVolume", false}, "volumedown": {0x1008ff11, "XF86AudioLowerVolume", false}, "mute": {0x1008ff12, "XF86AudioMute", false},
	"playpause": {0x1008ff14, "XF86AudioPlay", false}, "next": {0x1008ff17, "XF86AudioNext", false}, "previous": {0x1008ff16, "XF86AudioPrev", false},
	"brightnessup": {0x1008ff02, "XF86MonBrightnessUp", false}, "brightnessdown": {0x1008ff03, "XF86MonBrightnessDown", false},
}

var punctNames = map[rune]string{
	'-': "minus", '=': "equal", ',': "comma", '.': "period", '/': "slash", ';': "semicolon", '\'': "apostrophe",
	'[': "bracketleft", ']': "bracketright", '\\': "backslash", '`': "grave", '+': "plus", '*': "asterisk",
}

func runeKeysym(r rune) uint32 {
	switch r {
	case '\n':
		return 0xff0d
	case '\t':
		return 0xff09
	}
	if (r >= 0x20 && r <= 0x7e) || (r >= 0xa0 && r <= 0xff) {
		return uint32(r)
	}
	return 0x01000000 | uint32(r)
}

func parseKeyCombo(s string) (keyCombo, error) {
	var k keyCombo
	s = strings.TrimSpace(s)
	if s == "" {
		return k, fmt.Errorf("empty key")
	}
	if len(s) > 60 {
		return k, fmt.Errorf("key %q is too long", s)
	}
	parts := strings.Split(s, "+")
	if strings.HasSuffix(s, "++") || s == "+" {
		parts = append(strings.Split(strings.TrimSuffix(s, "++"), "+"), "+")
		if s == "+" {
			parts = []string{"+"}
		}
	}
	for i, p := range parts {
		last := i == len(parts)-1
		lp := strings.ToLower(strings.TrimSpace(p))
		if !last {
			m, ok := modKeys[lp]
			if !ok {
				return k, fmt.Errorf("%q is not a modifier (ctrl, shift, alt, super, altgr)", p)
			}
			for _, x := range k.mods {
				if x.sym == m.sym {
					return k, fmt.Errorf("modifier %q given twice", p)
				}
			}
			k.mods = append(k.mods, m)
			continue
		}
		if m, ok := modKeys[lp]; ok && len(parts) == 1 {
			k.key = keyDef{m.sym, map[string]string{"ctrl": "Control_L", "shift": "Shift_L", "alt": "Alt_L", "logo": "Super_L", "altgr": "ISO_Level3_Shift"}[m.name], false}
			continue
		}
		if d, ok := namedKeys[lp]; ok {
			k.key = d
			continue
		}
		if len(lp) >= 2 && lp[0] == 'f' {
			if n, err := strconv.Atoi(lp[1:]); err == nil && n >= 1 && n <= 24 {
				k.key = keyDef{uint32(0xffbe + n - 1), "F" + strconv.Itoa(n), false}
				continue
			}
		}
		if utf8.RuneCountInString(p) == 1 {
			r, _ := utf8.DecodeRuneInString(p)
			if unicode.IsControl(r) {
				return k, fmt.Errorf("control characters are not keys")
			}
			if len(k.mods) > 0 {
				r = unicode.ToLower(r)
			}
			name := string(r)
			if n, ok := punctNames[r]; ok {
				name = n
			} else if r == ' ' {
				name = "space"
			}
			k.key = keyDef{runeKeysym(r), name, false}
			continue
		}
		return k, fmt.Errorf("unknown key %q (letters, digits, punctuation, enter, escape, tab, backspace, delete, home, end, pageup, pagedown, arrows, space, f1-f24, or a modifier)", p)
	}
	if len(k.mods) > 4 {
		return k, fmt.Errorf("too many modifiers")
	}
	return k, nil
}

func (k keyCombo) String() string {
	var p []string
	for _, m := range k.mods {
		p = append(p, m.name)
	}
	return strings.Join(append(p, k.key.name), "+")
}

func (k keyCombo) wtypeArgs() []string {
	var a []string
	for _, m := range k.mods {
		a = append(a, "-M", m.name)
	}
	a = append(a, "-k", k.key.name)
	for i := len(k.mods) - 1; i >= 0; i-- {
		a = append(a, "-m", k.mods[i].name)
	}
	return a
}
