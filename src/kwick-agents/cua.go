package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"strings"
	"sync"
)

type kwickCaller func(name string, args map[string]any) (map[string]any, error)

func brokerCaller(sock string) (kwickCaller, func(), error) {
	conn, err := net.Dial("unix", sock)
	if err != nil {
		return nil, nil, err
	}
	r := bufio.NewReaderSize(conn, 1<<20)
	var mu sync.Mutex
	seq := 0
	rpc := func(method string, params any) (json.RawMessage, error) {
		mu.Lock()
		defer mu.Unlock()
		seq++
		b, _ := json.Marshal(map[string]any{"jsonrpc": "2.0", "id": seq, "method": method, "params": params})
		if _, err := conn.Write(append(b, '\n')); err != nil {
			return nil, err
		}
		for {
			line, err := r.ReadBytes('\n')
			if err != nil {
				return nil, err
			}
			var m struct {
				ID     int             `json:"id"`
				Result json.RawMessage `json:"result"`
				Error  *rpcErr         `json:"error"`
			}
			if json.Unmarshal(line, &m) != nil || m.ID != seq {
				continue
			}
			if m.Error != nil {
				return nil, fmt.Errorf("%s", m.Error.Message)
			}
			return m.Result, nil
		}
	}
	if _, err := rpc("initialize", map[string]any{"protocolVersion": "2025-06-18", "capabilities": map[string]any{}, "clientInfo": map[string]any{"name": "computer use", "version": version}}); err != nil {
		conn.Close()
		return nil, nil, err
	}
	call := func(name string, args map[string]any) (map[string]any, error) {
		raw, err := rpc("tools/call", map[string]any{"name": name, "arguments": args})
		if err != nil {
			return nil, err
		}
		var res map[string]any
		if err := json.Unmarshal(raw, &res); err != nil {
			return nil, err
		}
		return res, nil
	}
	return call, func() { conn.Close() }, nil
}

func resultText(res map[string]any) string {
	cs, _ := res["content"].([]any)
	var out []string
	for _, c := range cs {
		if m, ok := c.(map[string]any); ok && m["type"] == "text" {
			s, _ := m["text"].(string)
			out = append(out, s)
		}
	}
	if len(out) == 0 {
		if cm, ok := res["content"].([]map[string]any); ok {
			for _, m := range cm {
				if m["type"] == "text" {
					s, _ := m["text"].(string)
					out = append(out, s)
				}
			}
		}
	}
	return strings.Join(out, "\n")
}

func normalizeResult(res map[string]any) map[string]any {
	b, _ := json.Marshal(res)
	var out map[string]any
	json.Unmarshal(b, &out)
	return out
}

type cuaGeom struct {
	ox, oy, scale float64
}

type cuaDriver struct {
	call    kwickCaller
	mu      sync.Mutex
	ids     map[string]int
	uuids   map[int]string
	geom    map[int]cuaGeom
	lastWin int
	next    int
}

func (d *cuaDriver) do(name string, args map[string]any) (map[string]any, error) {
	res, err := d.call(name, args)
	if err != nil {
		return nil, err
	}
	res = normalizeResult(res)
	if e, _ := res["isError"].(bool); e {
		return nil, fmt.Errorf("%s", resultText(res))
	}
	return res, nil
}

func (d *cuaDriver) windowID(uuid string) int {
	d.mu.Lock()
	defer d.mu.Unlock()
	if id, ok := d.ids[uuid]; ok {
		return id
	}
	d.next++
	d.ids[uuid] = d.next
	d.uuids[d.next] = uuid
	return d.next
}

func (d *cuaDriver) windows() ([]map[string]any, error) {
	res, err := d.do("windows_list", map[string]any{})
	if err != nil {
		return nil, err
	}
	sc, _ := res["structuredContent"].(map[string]any)
	ws, _ := sc["windows"].([]any)
	var out []map[string]any
	for i, w := range ws {
		m, _ := w.(map[string]any)
		if m == nil {
			continue
		}
		id, _ := m["id"].(string)
		pid, _ := m["pid"].(float64)
		out = append(out, map[string]any{
			"window_id": d.windowID(id), "pid": int(pid), "app_name": m["app"], "title": m["title"],
			"bounds": map[string]any{"x": m["x"], "y": m["y"], "width": m["width"], "height": m["height"]},
			"x":      m["x"], "y": m["y"], "width": m["width"], "height": m["height"],
			"is_on_screen": m["minimized"] != true, "is_active": m["active"] == true, "z_index": len(ws) - i,
			"protected": m["protected"],
		})
	}
	return out, nil
}

func (d *cuaDriver) findWindow(a map[string]any) (map[string]any, int, error) {
	ws, err := d.windows()
	if err != nil {
		return nil, 0, err
	}
	want := argInt(a, "window_id", 0)
	pid := argInt(a, "pid", 0)
	for _, w := range ws {
		if want != 0 && w["window_id"] == want {
			return w, want, nil
		}
	}
	for _, w := range ws {
		if want == 0 && pid != 0 && w["pid"] == pid {
			return w, w["window_id"].(int), nil
		}
	}
	if want == 0 && pid == 0 {
		for _, w := range ws {
			if w["is_active"] == true {
				return w, w["window_id"].(int), nil
			}
		}
	}
	return nil, 0, fmt.Errorf("no such window (call list_windows)")
}

func num(v any) float64 {
	switch x := v.(type) {
	case float64:
		return x
	case int:
		return float64(x)
	}
	return 0
}

func (d *cuaDriver) point(a map[string]any, xk, yk string) (map[string]any, error) {
	x, okx := argNum(a, xk)
	y, oky := argNum(a, yk)
	if !okx || !oky {
		return nil, fmt.Errorf("%s and %s are required (element indexes are not supported on KwickOS; use coordinates from the screenshot)", xk, yk)
	}
	wid := argInt(a, "window_id", 0)
	if wid == 0 {
		d.mu.Lock()
		wid = d.lastWin
		d.mu.Unlock()
	}
	d.mu.Lock()
	g, ok := d.geom[wid]
	d.mu.Unlock()
	if !ok {
		w, id, err := d.findWindow(map[string]any{"window_id": float64(wid), "pid": a["pid"]})
		if err != nil {
			return map[string]any{"x": x, "y": y, "space": "screen"}, nil
		}
		b := w["bounds"].(map[string]any)
		g = cuaGeom{num(b["x"]), num(b["y"]), 1}
		wid = id
	}
	return map[string]any{"x": g.ox + x*g.scale, "y": g.oy + y*g.scale, "space": "screen"}, nil
}

func (d *cuaDriver) focusTarget(a map[string]any) error {
	if argInt(a, "window_id", 0) == 0 && argInt(a, "pid", 0) == 0 {
		return nil
	}
	w, id, err := d.findWindow(a)
	if err != nil {
		return err
	}
	if w["is_active"] == true {
		return nil
	}
	d.mu.Lock()
	uuid := d.uuids[id]
	d.mu.Unlock()
	_, err = d.do("window_focus", map[string]any{"id": uuid})
	return err
}

func (d *cuaDriver) shot(a map[string]any) (map[string]any, error) {
	args := map[string]any{"max_width": 1568, "max_height": 1568}
	if f := argStr(a, "format"); f == "jpeg" || f == "jpg" {
		args["format"] = "jpeg"
		args["quality"] = argInt(a, "quality", 85)
	}
	wid := 0
	if argInt(a, "window_id", 0) != 0 || argInt(a, "pid", 0) != 0 {
		w, id, err := d.findWindow(a)
		if err != nil {
			return nil, err
		}
		b := w["bounds"].(map[string]any)
		args["region"] = map[string]any{"x": b["x"], "y": b["y"], "width": b["width"], "height": b["height"]}
		wid = id
	}
	res, err := d.do("screenshot", args)
	if err != nil {
		return nil, err
	}
	sc, _ := res["structuredContent"].(map[string]any)
	d.mu.Lock()
	d.geom[wid] = cuaGeom{num(sc["origin_x"]), num(sc["origin_y"]), num(sc["scale"])}
	d.lastWin = wid
	d.mu.Unlock()
	var content []any
	cs, _ := res["content"].([]any)
	for _, c := range cs {
		if m, ok := c.(map[string]any); ok && m["type"] == "image" {
			content = append(content, m)
		}
	}
	content = append(content, map[string]any{"type": "text", "text": fmt.Sprintf("Screenshot %vx%v of %s. Coordinates for click, drag and scroll are pixels of this image.",
		sc["width"], sc["height"], map[bool]string{true: "the window", false: "the screen"}[wid != 0])})
	return map[string]any{"content": content, "structuredContent": map[string]any{"width": sc["width"], "height": sc["height"], "window_id": wid}}, nil
}

func textResult(s string, data map[string]any) map[string]any {
	out := map[string]any{"content": []any{map[string]any{"type": "text", "text": s}}}
	if data != nil {
		out["structuredContent"] = data
	}
	return out
}

func (d *cuaDriver) click(a map[string]any, button string, double bool) (map[string]any, error) {
	p, err := d.point(a, "x", "y")
	if err != nil {
		return nil, err
	}
	p["button"] = button
	p["double"] = double
	if b := argStr(a, "button"); b != "" {
		p["button"] = b
	}
	if _, err := d.do("pointer_click", p); err != nil {
		return nil, err
	}
	return textResult("Clicked.", map[string]any{"x": p["x"], "y": p["y"]}), nil
}

func comboName(k string) string {
	k = strings.TrimSpace(strings.ToLower(k))
	switch k {
	case "command", "cmd", "meta", "win", "windows":
		return "super"
	case "control":
		return "ctrl"
	case "option":
		return "alt"
	case "arrowup":
		return "up"
	case "arrowdown":
		return "down"
	case "arrowleft":
		return "left"
	case "arrowright":
		return "right"
	}
	return k
}

func (d *cuaDriver) tool(name string, a map[string]any) (map[string]any, error) {
	switch name {
	case "list_windows":
		ws, err := d.windows()
		if err != nil {
			return nil, err
		}
		b, _ := json.Marshal(map[string]any{"windows": ws})
		return map[string]any{"content": []any{map[string]any{"type": "text", "text": string(b)}}, "structuredContent": map[string]any{"windows": ws}}, nil
	case "list_apps":
		ws, err := d.windows()
		if err != nil {
			return nil, err
		}
		var apps []map[string]any
		seen := map[string]bool{}
		for _, w := range ws {
			n, _ := w["app_name"].(string)
			if n == "" || seen[n] {
				continue
			}
			seen[n] = true
			apps = append(apps, map[string]any{"name": n, "pid": w["pid"], "running": true, "active": w["is_active"]})
		}
		return map[string]any{"content": []any{map[string]any{"type": "text", "text": fmt.Sprintf("%d running apps", len(apps))}}, "structuredContent": map[string]any{"apps": apps}}, nil
	case "screenshot", "get_window_state":
		return d.shot(a)
	case "bring_to_front":
		a2 := map[string]any{"window_id": a["window_id"], "pid": a["pid"]}
		_, id, err := d.findWindow(a2)
		if err != nil {
			return nil, err
		}
		d.mu.Lock()
		uuid := d.uuids[id]
		d.mu.Unlock()
		if _, err := d.do("window_focus", map[string]any{"id": uuid}); err != nil {
			return nil, err
		}
		return textResult("Raised the window.", nil), nil
	case "move_cursor":
		p, err := d.point(a, "x", "y")
		if err != nil {
			return nil, err
		}
		if _, err := d.do("pointer_move", p); err != nil {
			return nil, err
		}
		return textResult("Moved the pointer.", map[string]any{"x": p["x"], "y": p["y"]}), nil
	case "click":
		return d.click(a, "left", false)
	case "double_click":
		return d.click(a, "left", true)
	case "right_click":
		return d.click(a, "right", false)
	case "scroll":
		amount := argInt(a, "amount", 3)
		if amount < 1 {
			amount = 1
		}
		if amount > 30 {
			amount = 30
		}
		args := map[string]any{}
		switch argStr(a, "direction") {
		case "up":
			args["dy"] = -amount
		case "left":
			args["dx"] = -amount
		case "right":
			args["dx"] = amount
		default:
			args["dy"] = amount
		}
		if _, ok := a["x"]; ok {
			p, err := d.point(a, "x", "y")
			if err != nil {
				return nil, err
			}
			args["x"], args["y"], args["space"] = p["x"], p["y"], "screen"
		} else if w, _, err := d.findWindow(a); err == nil {
			b := w["bounds"].(map[string]any)
			args["x"], args["y"], args["space"] = num(b["x"])+num(b["width"])/2, num(b["y"])+num(b["height"])/2, "screen"
		}
		if _, err := d.do("scroll", args); err != nil {
			return nil, err
		}
		return textResult("Scrolled.", nil), nil
	case "drag":
		p0, err := d.point(a, "from_x", "from_y")
		if err != nil {
			return nil, err
		}
		p1, err := d.point(a, "to_x", "to_y")
		if err != nil {
			return nil, err
		}
		if _, err := d.do("pointer_drag", map[string]any{"from_x": p0["x"], "from_y": p0["y"], "to_x": p1["x"], "to_y": p1["y"], "space": "screen"}); err != nil {
			return nil, err
		}
		return textResult("Dragged.", nil), nil
	case "type_text", "type":
		if err := d.focusTarget(a); err != nil {
			return nil, err
		}
		if _, err := d.do("type_text", map[string]any{"text": argStr(a, "text")}); err != nil {
			return nil, err
		}
		return textResult("Typed.", nil), nil
	case "hotkey", "press_key", "key":
		if err := d.focusTarget(a); err != nil {
			return nil, err
		}
		var parts []string
		if name == "hotkey" {
			parts = argStrings(a, "keys")
		} else {
			parts = strings.Split(argStr(a, "key"), "+")
		}
		for i := range parts {
			parts[i] = comboName(parts[i])
		}
		if len(parts) == 0 || parts[0] == "" {
			return nil, fmt.Errorf("no key given")
		}
		if _, err := d.do("key_press", map[string]any{"keys": strings.Join(parts, "+")}); err != nil {
			return nil, err
		}
		return textResult("Pressed "+strings.Join(parts, "+")+".", nil), nil
	}
	return nil, fmt.Errorf("unknown tool %q", name)
}

func cuaTools() []map[string]any {
	n := map[string]any{"type": "number"}
	win := map[string]any{"pid": map[string]any{"type": "integer"}, "window_id": map[string]any{"type": "integer"}}
	with := func(extra map[string]any) map[string]any {
		p := map[string]any{}
		for k, v := range win {
			p[k] = v
		}
		for k, v := range extra {
			p[k] = v
		}
		return map[string]any{"type": "object", "properties": p}
	}
	t := func(name, desc string, schema map[string]any) map[string]any {
		return map[string]any{"name": name, "description": desc, "inputSchema": schema}
	}
	return []map[string]any{
		t("list_windows", "Open windows with pid, window_id, app_name, title, bounds and z_index.", with(map[string]any{"on_screen_only": map[string]any{"type": "boolean"}})),
		t("list_apps", "Running apps.", with(nil)),
		t("screenshot", "Screenshot of a window (window_id) or the whole screen.", with(map[string]any{"format": map[string]any{"type": "string"}, "quality": map[string]any{"type": "integer"}})),
		t("get_window_state", "Screenshot of a window.", with(nil)),
		t("bring_to_front", "Raise and focus a window.", with(nil)),
		t("move_cursor", "Move the pointer to x,y of the last screenshot.", with(map[string]any{"x": n, "y": n})),
		t("click", "Click at x,y of the window screenshot.", with(map[string]any{"x": n, "y": n, "button": map[string]any{"type": "string"}})),
		t("double_click", "Double-click at x,y.", with(map[string]any{"x": n, "y": n})),
		t("right_click", "Right-click at x,y.", with(map[string]any{"x": n, "y": n})),
		t("scroll", "Scroll a window.", with(map[string]any{"direction": map[string]any{"type": "string"}, "amount": map[string]any{"type": "integer"}, "x": n, "y": n})),
		t("drag", "Drag from one point to another.", with(map[string]any{"from_x": n, "from_y": n, "to_x": n, "to_y": n})),
		t("type_text", "Type text into the window.", with(map[string]any{"text": map[string]any{"type": "string"}})),
		t("hotkey", "Press a key combination.", with(map[string]any{"keys": map[string]any{"type": "array", "items": map[string]any{"type": "string"}}})),
		t("press_key", "Press one key.", with(map[string]any{"key": map[string]any{"type": "string"}})),
	}
}

func cuaMain(args []string) int {
	if len(args) == 0 || args[0] != "mcp" {
		fmt.Fprintln(os.Stderr, "usage: kwick-cua-driver mcp\nA cua-driver compatible MCP server that routes computer use through kwick-mcp (consent, indicator, audit).")
		return 2
	}
	var call kwickCaller
	sock, inSandbox := brokerSocket()
	if sock != "" {
		c, closeFn, err := brokerCaller(sock)
		if err == nil {
			defer closeFn()
			call = c
		} else if inSandbox {
			fmt.Fprintf(os.Stderr, "kwick-cua-driver: cannot reach the KwickOS broker: %v\n", err)
			return 1
		}
	}
	if call == nil {
		if os.Getenv("KWICK_AGENT_SANDBOX") == "1" {
			fmt.Fprintln(os.Stderr, "kwick-cua-driver: inside a sandbox without a broker")
			return 1
		}
		agent := os.Getenv("KWICK_AGENT")
		if agent == "" {
			agent = ancestorEnv("KWICK_AGENT")
		}
		if agent == "" {
			agent = "cybara"
		}
		s := newServer(agent, nil, false)
		s.client = "computer use"
		defer s.shared.stopControl("the computer use driver stopped")
		call = func(name string, a map[string]any) (map[string]any, error) {
			res, ok := s.callTool(name, a)
			if !ok {
				return nil, fmt.Errorf("unknown tool %s", name)
			}
			return res, nil
		}
	}
	d := &cuaDriver{call: call, ids: map[string]int{}, uuids: map[int]string{}, geom: map[int]cuaGeom{}}
	return serveCua(d, os.Stdin, os.Stdout)
}

func serveCua(d *cuaDriver, in io.Reader, out io.Writer) int {
	r := bufio.NewReaderSize(in, 1<<20)
	var omu sync.Mutex
	send := func(v any) {
		b, _ := json.Marshal(v)
		omu.Lock()
		out.Write(append(b, '\n'))
		omu.Unlock()
	}
	for {
		line, err := r.ReadBytes('\n')
		if len(strings.TrimSpace(string(line))) > 0 {
			var m rpcMsg
			if json.Unmarshal(line, &m) == nil && len(m.ID) > 0 && string(m.ID) != "null" {
				switch m.Method {
				case "initialize":
					send(map[string]any{"jsonrpc": "2.0", "id": m.ID, "result": map[string]any{"protocolVersion": "2024-11-05",
						"capabilities": map[string]any{"tools": map[string]any{}}, "serverInfo": map[string]any{"name": "kwick-cua-driver", "version": version}}})
				case "ping":
					send(map[string]any{"jsonrpc": "2.0", "id": m.ID, "result": map[string]any{}})
				case "tools/list":
					send(map[string]any{"jsonrpc": "2.0", "id": m.ID, "result": map[string]any{"tools": cuaTools()}})
				case "tools/call":
					var p struct {
						Name      string         `json:"name"`
						Arguments map[string]any `json:"arguments"`
					}
					json.Unmarshal(m.Params, &p)
					if p.Arguments == nil {
						p.Arguments = map[string]any{}
					}
					res, err := d.tool(p.Name, p.Arguments)
					if err != nil {
						res = map[string]any{"content": []any{map[string]any{"type": "text", "text": err.Error()}}, "isError": true}
					}
					send(map[string]any{"jsonrpc": "2.0", "id": m.ID, "result": res})
				default:
					send(map[string]any{"jsonrpc": "2.0", "id": m.ID, "error": rpcErr{-32601, "method not found: " + m.Method}})
				}
			}
		}
		if err != nil {
			return 0
		}
	}
}
