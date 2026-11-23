package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/godbus/dbus/v5"
)

const (
	bridgePath     = dbus.ObjectPath("/org/kwickos/agents")
	bridgeIface    = "org.kwickos.agents.Bridge"
	controlBusName = "org.kwickos.agents.Control"
	hotkeyPlugin   = "kwickagents_stop_key"
)

func (b *bus) kwinHotkey() {
	if !b.hasName("org.kde.KWin") {
		return
	}
	var loaded bool
	if b.conn.Object("org.kde.KWin", "/Scripting").Call("org.kde.kwin.Scripting.isScriptLoaded", 0, hotkeyPlugin).Store(&loaded) == nil && loaded {
		return
	}
	js := "registerShortcut(\"KwickAgentsStop\", \"Stop AI agent control (KwickOS)\", \"Meta+Alt+Escape\", function () {\n  callDBus(" +
		jsString(controlBusName) + ", " + jsString(string(bridgePath)) + ", " + jsString(bridgeIface) + ", \"Stop\", \"hotkey\");\n});\n"
	rd := runtimeDir()
	os.MkdirAll(rd, 0o700)
	f := filepath.Join(rd, "kwin-stop-hotkey.js")
	if os.WriteFile(f, []byte(js), 0o600) != nil {
		return
	}
	var sid int32
	if b.conn.Object("org.kde.KWin", "/Scripting").Call("org.kde.kwin.Scripting.loadScript", 0, f, hotkeyPlugin).Store(&sid) != nil || sid < 0 {
		return
	}
	b.conn.Object("org.kde.KWin", dbus.ObjectPath("/Scripting/Script"+strconv.Itoa(int(sid)))).Call("org.kde.kwin.Script.run", 0)
}

type bus struct {
	conn     *dbus.Conn
	mu       sync.Mutex
	handlers map[string]func(*dbus.Signal)
	waiters  map[string]chan string
	onStop   func(reason string)
	seq      int
}

var (
	sessMu   sync.Mutex
	sessConn *bus
)

func sessionBus() (*bus, error) {
	sessMu.Lock()
	defer sessMu.Unlock()
	if sessConn != nil && sessConn.conn.Connected() {
		return sessConn, nil
	}
	if os.Getenv("DBUS_SESSION_BUS_ADDRESS") == "" {
		p := fmt.Sprintf("/run/user/%d/bus", os.Getuid())
		if !exists(p) {
			return nil, fmt.Errorf("no D-Bus session bus (DBUS_SESSION_BUS_ADDRESS is not set)")
		}
		os.Setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path="+p)
	}
	c, err := dbus.ConnectSessionBus()
	if err != nil {
		return nil, fmt.Errorf("D-Bus session bus: %v", err)
	}
	b := &bus{conn: c, handlers: map[string]func(*dbus.Signal){}, waiters: map[string]chan string{}}
	ch := make(chan *dbus.Signal, 64)
	c.Signal(ch)
	go func() {
		for sg := range ch {
			b.mu.Lock()
			h := b.handlers[string(sg.Path)+"|"+sg.Name]
			if h == nil {
				h = b.handlers["*|"+sg.Name]
			}
			b.mu.Unlock()
			if h != nil {
				h(sg)
			}
		}
	}()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	c.Object(portalDest, portalPath).CallWithContext(ctx, "org.freedesktop.host.portal.Registry.Register", 0, "org.kwickos.agents", map[string]dbus.Variant{})
	cancel()
	if err := c.Export(&bridgeObj{b}, bridgePath, bridgeIface); err != nil {
		c.Close()
		return nil, err
	}
	sessConn = b
	return b, nil
}

func systemBusCall(dest, path, method string, args ...any) (*dbus.Call, error) {
	c, err := dbus.ConnectSystemBus()
	if err != nil {
		return nil, err
	}
	defer c.Close()
	call := c.Object(dest, dbus.ObjectPath(path)).Call(method, 0, args...)
	return call, call.Err
}

func systemBusProp(dest, path, prop string) (dbus.Variant, error) {
	c, err := dbus.ConnectSystemBus()
	if err != nil {
		return dbus.Variant{}, err
	}
	defer c.Close()
	return c.Object(dest, dbus.ObjectPath(path)).GetProperty(prop)
}

func systemBusSetProp(dest, path, prop string, v any) error {
	c, err := dbus.ConnectSystemBus()
	if err != nil {
		return err
	}
	defer c.Close()
	return c.Object(dest, dbus.ObjectPath(path)).SetProperty(prop, dbus.MakeVariant(v))
}

func (b *bus) name() string {
	if n := b.conn.Names(); len(n) > 0 {
		return n[0]
	}
	return ""
}

func (b *bus) on(path dbus.ObjectPath, iface, member string, h func(*dbus.Signal)) error {
	opts := []dbus.MatchOption{dbus.WithMatchInterface(iface), dbus.WithMatchMember(member)}
	key := "*|" + iface + "." + member
	if path != "" {
		opts = append(opts, dbus.WithMatchObjectPath(path))
		key = string(path) + "|" + iface + "." + member
	}
	b.mu.Lock()
	b.handlers[key] = h
	b.mu.Unlock()
	return b.conn.AddMatchSignal(opts...)
}

func (b *bus) off(path dbus.ObjectPath, iface, member string) {
	key := "*|" + iface + "." + member
	opts := []dbus.MatchOption{dbus.WithMatchInterface(iface), dbus.WithMatchMember(member)}
	if path != "" {
		key = string(path) + "|" + iface + "." + member
		opts = append(opts, dbus.WithMatchObjectPath(path))
	}
	b.mu.Lock()
	delete(b.handlers, key)
	b.mu.Unlock()
	b.conn.RemoveMatchSignal(opts...)
}

func (b *bus) owner(name string) string {
	var o string
	if b.conn.BusObject().Call("org.freedesktop.DBus.GetNameOwner", 0, name).Store(&o) != nil {
		return ""
	}
	return o
}

func (b *bus) hasName(name string) bool { return b.owner(name) != "" }

type bridgeObj struct{ b *bus }

func (o *bridgeObj) Result(sender dbus.Sender, id, data string) *dbus.Error {
	if kw := o.b.owner("org.kde.KWin"); kw == "" || string(sender) != kw {
		return dbus.MakeFailedError(fmt.Errorf("not KWin"))
	}
	o.b.mu.Lock()
	ch := o.b.waiters[id]
	delete(o.b.waiters, id)
	o.b.mu.Unlock()
	if ch != nil {
		ch <- data
	}
	return nil
}

func (o *bridgeObj) Stop(sender dbus.Sender, reason string) *dbus.Error {
	o.b.mu.Lock()
	f := o.b.onStop
	o.b.mu.Unlock()
	if f != nil {
		go f(reason)
	}
	return nil
}

func jsString(s string) string {
	b, _ := json.Marshal(s)
	return string(b)
}

func (b *bus) kwinLoad(js, tag string) (string, error) {
	if !b.hasName("org.kde.KWin") {
		return "", fmt.Errorf("KWin is not running on this session bus")
	}
	rd := runtimeDir()
	os.MkdirAll(rd, 0o700)
	b.mu.Lock()
	b.seq++
	id := fmt.Sprintf("%s%d_%d", tag, os.Getpid(), b.seq)
	b.mu.Unlock()
	f := filepath.Join(rd, "kwin-"+id+".js")
	if err := os.WriteFile(f, []byte(js), 0o600); err != nil {
		return "", err
	}
	plugin := "kwickagents_" + id
	var sid int32
	ko := b.conn.Object("org.kde.KWin", "/Scripting")
	if err := ko.Call("org.kde.kwin.Scripting.loadScript", 0, f, plugin).Store(&sid); err != nil {
		os.Remove(f)
		return "", fmt.Errorf("KWin loadScript: %v", err)
	}
	if sid < 0 {
		os.Remove(f)
		return "", fmt.Errorf("KWin refused the script")
	}
	if err := b.conn.Object("org.kde.KWin", dbus.ObjectPath("/Scripting/Script"+strconv.Itoa(int(sid)))).Call("org.kde.kwin.Script.run", 0).Err; err != nil {
		b.kwinUnload(plugin, f)
		return "", fmt.Errorf("KWin script run: %v", err)
	}
	return plugin + "\x00" + f, nil
}

func (b *bus) kwinUnload(plugin, file string) {
	b.conn.Object("org.kde.KWin", "/Scripting").Call("org.kde.kwin.Scripting.unloadScript", 0, plugin)
	if file != "" {
		os.Remove(file)
	}
}

func (b *bus) kwinUnloadHandle(h string) {
	p := strings.SplitN(h, "\x00", 2)
	if len(p) == 2 {
		b.kwinUnload(p[0], p[1])
	}
}

func (b *bus) kwinEval(body string, timeout time.Duration) (json.RawMessage, error) {
	b.mu.Lock()
	b.seq++
	rid := fmt.Sprintf("r%d", b.seq)
	ch := make(chan string, 1)
	b.waiters[rid] = ch
	b.mu.Unlock()
	defer func() {
		b.mu.Lock()
		delete(b.waiters, rid)
		b.mu.Unlock()
	}()
	js := "(function () {\nvar __r;\ntry { __r = (function () {\n" + body + "\n})(); } catch (e) { __r = { error: String(e) }; }\ncallDBus(" +
		jsString(b.name()) + ", " + jsString(string(bridgePath)) + ", " + jsString(bridgeIface) + ", \"Result\", " + jsString(rid) +
		", JSON.stringify(__r === undefined ? null : __r));\n})();\n"
	h, err := b.kwinLoad(js, "e")
	if err != nil {
		return nil, err
	}
	defer b.kwinUnloadHandle(h)
	select {
	case s := <-ch:
		var probe struct {
			Error string `json:"error"`
		}
		if json.Unmarshal([]byte(s), &probe) == nil && probe.Error != "" {
			return nil, fmt.Errorf("KWin script: %s", probe.Error)
		}
		return json.RawMessage(s), nil
	case <-time.After(timeout):
		return nil, fmt.Errorf("KWin did not answer within %s", timeout)
	}
}

type notifyHandle struct {
	b  *bus
	id uint32
}

func (b *bus) notify(summary, body, icon string, urgency byte, resident bool, actions []string, onAction func(string), onClosed func(uint32)) (*notifyHandle, error) {
	hints := map[string]dbus.Variant{"urgency": dbus.MakeVariant(urgency), "desktop-entry": dbus.MakeVariant("org.kwickos.agents")}
	if resident {
		hints["resident"] = dbus.MakeVariant(true)
	}
	timeout := int32(-1)
	if resident {
		timeout = 0
	}
	if actions == nil {
		actions = []string{}
	}
	var id uint32
	err := b.conn.Object("org.freedesktop.Notifications", "/org/freedesktop/Notifications").Call("org.freedesktop.Notifications.Notify", 0,
		"KwickOS Agents", uint32(0), icon, summary, body, actions, hints, timeout).Store(&id)
	if err != nil {
		return nil, err
	}
	h := &notifyHandle{b, id}
	if onAction != nil {
		b.on("/org/freedesktop/Notifications", "org.freedesktop.Notifications", "ActionInvoked", func(sg *dbus.Signal) {
			if len(sg.Body) == 2 {
				if nid, _ := sg.Body[0].(uint32); nid == id {
					a, _ := sg.Body[1].(string)
					onAction(a)
				}
			}
		})
	}
	if onClosed != nil {
		b.on("/org/freedesktop/Notifications", "org.freedesktop.Notifications", "NotificationClosed", func(sg *dbus.Signal) {
			if len(sg.Body) == 2 {
				if nid, _ := sg.Body[0].(uint32); nid == id {
					r, _ := sg.Body[1].(uint32)
					onClosed(r)
				}
			}
		})
	}
	return h, nil
}

func (h *notifyHandle) close() {
	if h == nil {
		return
	}
	h.b.off("/org/freedesktop/Notifications", "org.freedesktop.Notifications", "ActionInvoked")
	h.b.off("/org/freedesktop/Notifications", "org.freedesktop.Notifications", "NotificationClosed")
	h.b.conn.Object("org.freedesktop.Notifications", "/org/freedesktop/Notifications").Call("org.freedesktop.Notifications.CloseNotification", 0, h.id)
}

func (b *bus) screenLocked() bool {
	var on bool
	for _, d := range []struct{ name, path, iface string }{
		{"org.freedesktop.ScreenSaver", "/ScreenSaver", "org.freedesktop.ScreenSaver"},
		{"org.gnome.ScreenSaver", "/org/gnome/ScreenSaver", "org.gnome.ScreenSaver"},
	} {
		if !b.hasName(d.name) {
			continue
		}
		if b.conn.Object(d.name, dbus.ObjectPath(d.path)).Call(d.iface+".GetActive", 0).Store(&on) == nil && on {
			return true
		}
	}
	return false
}
