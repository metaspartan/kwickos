package main

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

func fakeKwick(calls *[]string, last *map[string]any) kwickCaller {
	return func(name string, a map[string]any) (map[string]any, error) {
		*calls = append(*calls, name)
		*last = a
		switch name {
		case "windows_list":
			return map[string]any{"structuredContent": map[string]any{"windows": []any{
				map[string]any{"id": "{w1}", "title": "notes - Kate", "app": "org.kde.kate", "pid": float64(42), "x": float64(200), "y": float64(120), "width": float64(1100), "height": float64(700), "active": true},
				map[string]any{"id": "{w2}", "title": "Home", "app": "org.kde.dolphin", "pid": float64(43), "x": float64(0), "y": float64(0), "width": float64(800), "height": float64(600), "active": false},
			}}}, nil
		case "screenshot":
			return map[string]any{"content": []any{map[string]any{"type": "image", "data": "AAAA", "mimeType": "image/png"}},
				"structuredContent": map[string]any{"width": float64(550), "height": float64(350), "origin_x": float64(200), "origin_y": float64(120), "scale": float64(2)}}, nil
		case "type_text":
			return map[string]any{"content": []any{map[string]any{"type": "text", "text": "Refused: the focused window is a password prompt"}}, "isError": true}, nil
		}
		return map[string]any{"content": []any{map[string]any{"type": "text", "text": "ok"}}}, nil
	}
}

func TestCuaDriverTranslation(t *testing.T) {
	var calls []string
	var last map[string]any
	d := &cuaDriver{call: fakeKwick(&calls, &last), ids: map[string]int{}, uuids: map[int]string{}, geom: map[int]cuaGeom{}}
	res, err := d.tool("list_windows", map[string]any{"on_screen_only": true})
	if err != nil {
		t.Fatal(err)
	}
	ws := res["structuredContent"].(map[string]any)["windows"].([]map[string]any)
	if len(ws) != 2 || ws[0]["window_id"] != 1 || ws[0]["pid"] != 42 || ws[0]["app_name"] != "org.kde.kate" || ws[0]["z_index"] != 2 {
		t.Fatalf("windows %v", ws)
	}
	if _, err := d.tool("screenshot", map[string]any{"window_id": float64(1), "format": "jpeg"}); err != nil {
		t.Fatal(err)
	}
	if r := last["region"].(map[string]any); r["x"] != float64(200) || last["format"] != "jpeg" {
		t.Fatalf("screenshot args %v", last)
	}
	if _, err := d.tool("click", map[string]any{"window_id": float64(1), "x": float64(10), "y": float64(20)}); err != nil {
		t.Fatal(err)
	}
	if last["x"] != float64(220) || last["y"] != float64(160) || last["space"] != "screen" || last["button"] != "left" {
		t.Fatalf("click mapped to %v", last)
	}
	if _, err := d.tool("right_click", map[string]any{"window_id": float64(1), "x": float64(0), "y": float64(0)}); err != nil || last["button"] != "right" {
		t.Fatalf("right click %v %v", last, err)
	}
	if _, err := d.tool("hotkey", map[string]any{"keys": []any{"Command", "Shift", "t"}}); err != nil || last["keys"] != "super+shift+t" {
		t.Fatalf("hotkey %v %v", last, err)
	}
	if _, err := d.tool("click", map[string]any{"element_index": float64(3)}); err == nil {
		t.Fatal("element index without coordinates accepted")
	}
	if _, err := d.tool("type_text", map[string]any{"text": "pw"}); err == nil || !strings.Contains(err.Error(), "Refused") {
		t.Fatalf("refusal not passed through: %v", err)
	}
	if _, err := d.tool("scroll", map[string]any{"window_id": float64(2), "direction": "up", "amount": float64(4)}); err != nil || last["dy"] != -4 || last["x"] != float64(400) {
		t.Fatalf("scroll %v %v", last, err)
	}
}

func TestCuaServeProtocol(t *testing.T) {
	var calls []string
	var last map[string]any
	d := &cuaDriver{call: fakeKwick(&calls, &last), ids: map[string]int{}, uuids: map[int]string{}, geom: map[int]cuaGeom{}}
	in := strings.NewReader(`{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"type_text","arguments":{"text":"x"}}}
`)
	var out bytes.Buffer
	serveCua(d, in, &out)
	lines := strings.Split(strings.TrimSpace(out.String()), "\n")
	if len(lines) != 3 {
		t.Fatalf("got %d replies: %s", len(lines), out.String())
	}
	var tl struct {
		Result struct {
			Tools []map[string]any `json:"tools"`
		} `json:"result"`
	}
	json.Unmarshal([]byte(lines[1]), &tl)
	names := map[string]bool{}
	for _, tt := range tl.Result.Tools {
		names[tt["name"].(string)] = true
	}
	for _, n := range []string{"list_windows", "screenshot", "click", "type_text", "hotkey", "press_key", "scroll", "drag", "bring_to_front"} {
		if !names[n] {
			t.Fatalf("missing driver tool %s", n)
		}
	}
	if !strings.Contains(lines[2], `"isError":true`) {
		t.Fatalf("error not reported: %s", lines[2])
	}
}
