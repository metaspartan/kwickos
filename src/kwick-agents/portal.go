package main

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/godbus/dbus/v5"
)

const (
	portalDest = "org.freedesktop.portal.Desktop"
	portalPath = dbus.ObjectPath("/org/freedesktop/portal/desktop")
	rdIface    = "org.freedesktop.portal.RemoteDesktop"
	scIface    = "org.freedesktop.portal.ScreenCast"
)

type portalStream struct {
	node       uint32
	x, y, w, h int32
}

type portalBackend struct {
	b       *bus
	session dbus.ObjectPath
	streams []portalStream
	mu      sync.Mutex
	closed  bool
	onClose func()
}

func portalToken() string {
	r := make([]byte, 6)
	rand.Read(r)
	return "kwick" + hex.EncodeToString(r)
}

func restoreTokenPath() string { return filepath.Join(userScope().State, "remote-desktop.token") }

func (b *bus) portalRequest(iface, method string, timeout time.Duration, args func(token string) []any) (map[string]dbus.Variant, error) {
	tok := portalToken()
	sender := strings.ReplaceAll(strings.TrimPrefix(b.name(), ":"), ".", "_")
	reqPath := dbus.ObjectPath("/org/freedesktop/portal/desktop/request/" + sender + "/" + tok)
	type resp struct {
		code    uint32
		results map[string]dbus.Variant
	}
	ch := make(chan resp, 1)
	if err := b.on(reqPath, "org.freedesktop.portal.Request", "Response", func(sg *dbus.Signal) {
		if len(sg.Body) == 2 {
			c, _ := sg.Body[0].(uint32)
			r, _ := sg.Body[1].(map[string]dbus.Variant)
			select {
			case ch <- resp{c, r}:
			default:
			}
		}
	}); err != nil {
		return nil, err
	}
	defer b.off(reqPath, "org.freedesktop.portal.Request", "Response")
	var handle dbus.ObjectPath
	if err := b.conn.Object(portalDest, portalPath).Call(iface+"."+method, 0, args(tok)...).Store(&handle); err != nil {
		return nil, fmt.Errorf("%s.%s: %v", iface, method, err)
	}
	select {
	case r := <-ch:
		switch r.code {
		case 0:
			return r.results, nil
		case 1:
			return nil, fmt.Errorf("the request was cancelled in the system dialog")
		}
		return nil, fmt.Errorf("%s.%s failed (response %d)", iface, method, r.code)
	case <-time.After(timeout):
		b.conn.Object(portalDest, handle).Call("org.freedesktop.portal.Request.Close", 0)
		return nil, fmt.Errorf("no answer from the remote desktop portal within %s", timeout)
	}
}

func portalAvailable(b *bus) (uint32, bool) {
	if !b.hasName(portalDest) {
		b.conn.BusObject().Call("org.freedesktop.DBus.StartServiceByName", 0, portalDest, uint32(0))
	}
	v, err := b.conn.Object(portalDest, portalPath).GetProperty(rdIface + ".AvailableDeviceTypes")
	if err != nil {
		return 0, false
	}
	t, _ := v.Value().(uint32)
	return t, t&3 == 3
}

func newPortalBackend(b *bus) (*portalBackend, error) {
	if _, ok := portalAvailable(b); !ok {
		return nil, fmt.Errorf("the xdg-desktop-portal RemoteDesktop interface is not available in this session")
	}
	res, err := b.portalRequest(rdIface, "CreateSession", 60*time.Second, func(tok string) []any {
		return []any{map[string]dbus.Variant{"handle_token": dbus.MakeVariant(tok), "session_handle_token": dbus.MakeVariant(portalToken())}}
	})
	if err != nil {
		return nil, err
	}
	sh, _ := res["session_handle"].Value().(string)
	if sh == "" {
		if op, ok := res["session_handle"].Value().(dbus.ObjectPath); ok {
			sh = string(op)
		}
	}
	if sh == "" {
		return nil, fmt.Errorf("the portal returned no session")
	}
	p := &portalBackend{b: b, session: dbus.ObjectPath(sh)}
	ok := false
	defer func() {
		if !ok {
			p.close()
		}
	}()
	devOpts := func(tok string) []any {
		o := map[string]dbus.Variant{"handle_token": dbus.MakeVariant(tok), "types": dbus.MakeVariant(uint32(3)), "persist_mode": dbus.MakeVariant(uint32(2))}
		if t, err := os.ReadFile(restoreTokenPath()); err == nil && len(strings.TrimSpace(string(t))) > 0 {
			o["restore_token"] = dbus.MakeVariant(strings.TrimSpace(string(t)))
		}
		return []any{p.session, o}
	}
	if _, err := b.portalRequest(rdIface, "SelectDevices", 60*time.Second, devOpts); err != nil {
		return nil, err
	}
	if _, err := b.portalRequest(scIface, "SelectSources", 60*time.Second, func(tok string) []any {
		return []any{p.session, map[string]dbus.Variant{"handle_token": dbus.MakeVariant(tok), "types": dbus.MakeVariant(uint32(1)), "multiple": dbus.MakeVariant(true), "cursor_mode": dbus.MakeVariant(uint32(1))}}
	}); err != nil {
		return nil, err
	}
	res, err = b.portalRequest(rdIface, "Start", 180*time.Second, func(tok string) []any {
		return []any{p.session, "", map[string]dbus.Variant{"handle_token": dbus.MakeVariant(tok)}}
	})
	if err != nil {
		return nil, err
	}
	if d, _ := res["devices"].Value().(uint32); d&3 != 3 {
		return nil, fmt.Errorf("keyboard and pointer control were not granted in the system dialog")
	}
	if t, _ := res["restore_token"].Value().(string); t != "" {
		os.MkdirAll(filepath.Dir(restoreTokenPath()), 0o700)
		writeFileAtomic(restoreTokenPath(), []byte(t+"\n"), 0o600)
	}
	if sv, ok := res["streams"]; ok {
		p.streams = parseStreams(sv.Value())
	}
	if len(p.streams) == 0 {
		return nil, fmt.Errorf("no screen was shared in the system dialog; absolute pointer positions need one")
	}
	b.on(p.session, "org.freedesktop.portal.Session", "Closed", func(*dbus.Signal) {
		p.mu.Lock()
		p.closed = true
		f := p.onClose
		p.mu.Unlock()
		if f != nil {
			go f()
		}
	})
	ok = true
	return p, nil
}

func parseStreams(v any) []portalStream {
	var out []portalStream
	add := func(node uint32, props map[string]dbus.Variant) {
		s := portalStream{node: node}
		if pv, ok := props["position"]; ok {
			s.x, s.y = pair(pv.Value())
		}
		if sv, ok := props["size"]; ok {
			s.w, s.h = pair(sv.Value())
		}
		out = append(out, s)
	}
	switch arr := v.(type) {
	case [][]any:
		for _, st := range arr {
			if len(st) == 2 {
				n, _ := st[0].(uint32)
				pr, _ := st[1].(map[string]dbus.Variant)
				add(n, pr)
			}
		}
	case []any:
		for _, x := range arr {
			if st, ok := x.([]any); ok && len(st) == 2 {
				n, _ := st[0].(uint32)
				pr, _ := st[1].(map[string]dbus.Variant)
				add(n, pr)
			}
		}
	}
	return out
}

func pair(v any) (int32, int32) {
	switch x := v.(type) {
	case []any:
		if len(x) == 2 {
			a, _ := x[0].(int32)
			b, _ := x[1].(int32)
			return a, b
		}
	case []int32:
		if len(x) == 2 {
			return x[0], x[1]
		}
	}
	return 0, 0
}

func (p *portalBackend) name() string { return "xdg-desktop-portal RemoteDesktop" }

func (p *portalBackend) alive() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return !p.closed
}

func (p *portalBackend) call(method string, args ...any) error {
	if !p.alive() {
		return fmt.Errorf("the remote desktop session was closed")
	}
	all := append([]any{p.session, map[string]dbus.Variant{}}, args...)
	return p.b.conn.Object(portalDest, portalPath).Call(rdIface+"."+method, 0, all...).Err
}

func (p *portalBackend) move(x, y float64) error {
	for _, s := range p.streams {
		if x >= float64(s.x) && y >= float64(s.y) && x < float64(s.x+s.w) && y < float64(s.y+s.h) {
			return p.call("NotifyPointerMotionAbsolute", s.node, x-float64(s.x), y-float64(s.y))
		}
	}
	return fmt.Errorf("%.0f,%.0f is not on any shared screen", x, y)
}

var evdevButtons = map[string]int32{"left": 0x110, "right": 0x111, "middle": 0x112, "back": 0x113, "forward": 0x114}

func (p *portalBackend) button(btn string, down bool) error {
	code, ok := evdevButtons[btn]
	if !ok {
		return fmt.Errorf("unknown button %q", btn)
	}
	st := uint32(0)
	if down {
		st = 1
	}
	return p.call("NotifyPointerButton", code, st)
}

func (p *portalBackend) scroll(dx, dy int) error {
	if dy != 0 {
		if err := p.call("NotifyPointerAxisDiscrete", uint32(0), int32(dy)); err != nil {
			return err
		}
	}
	if dx != 0 {
		return p.call("NotifyPointerAxisDiscrete", uint32(1), int32(dx))
	}
	return nil
}

func (p *portalBackend) keysym(sym uint32, down bool) error {
	st := uint32(0)
	if down {
		st = 1
	}
	return p.call("NotifyKeyboardKeysym", int32(sym), st)
}

func (p *portalBackend) modifier(m keyDef, down bool) error {
	err := p.keysym(m.sym, down)
	time.Sleep(modDelay)
	return err
}

const modDelay = 40 * time.Millisecond

func (p *portalBackend) combo(k keyCombo) error {
	if len(k.mods) > 0 {
		time.Sleep(modDelay)
	}
	for _, m := range k.mods {
		if err := p.modifier(m, true); err != nil {
			return err
		}
	}
	err := p.keysym(k.key.sym, true)
	if err == nil {
		time.Sleep(25 * time.Millisecond)
		err = p.keysym(k.key.sym, false)
	}
	time.Sleep(modDelay)
	for i := len(k.mods) - 1; i >= 0; i-- {
		p.modifier(k.mods[i], false)
	}
	return err
}

func (p *portalBackend) typeText(s string) error {
	shift := keyDef{0xffe1, "shift", true}
	for _, r := range s {
		upper := r >= 'A' && r <= 'Z'
		sym := runeKeysym(r)
		if upper {
			sym = runeKeysym(r + ('a' - 'A'))
			if err := p.modifier(shift, true); err != nil {
				return err
			}
		}
		if err := p.keysym(sym, true); err != nil {
			return err
		}
		time.Sleep(8 * time.Millisecond)
		err := p.keysym(sym, false)
		if upper {
			time.Sleep(modDelay)
			p.modifier(shift, false)
		}
		if err != nil {
			return err
		}
		if r == '\n' || r == '\t' {
			time.Sleep(modDelay)
		} else {
			time.Sleep(12 * time.Millisecond)
		}
	}
	return nil
}

func (p *portalBackend) close() {
	p.mu.Lock()
	already := p.closed
	p.closed = true
	p.onClose = nil
	p.mu.Unlock()
	p.b.off(p.session, "org.freedesktop.portal.Session", "Closed")
	if !already {
		p.b.conn.Object(portalDest, p.session).Call("org.freedesktop.portal.Session.Close", 0)
	}
}

func (p *portalBackend) setOnClose(f func()) {
	p.mu.Lock()
	p.onClose = f
	p.mu.Unlock()
}

func (p *portalBackend) screens() []screenInfo {
	var out []screenInfo
	for i, s := range p.streams {
		out = append(out, screenInfo{Name: fmt.Sprintf("stream%d", i), X: int(s.x), Y: int(s.y), Width: int(s.w), Height: int(s.h), Scale: 1})
	}
	return out
}
