package main

import (
	"encoding/json"
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/godbus/dbus/v5"
)

type kdeDisplay struct {
	path    dbus.ObjectPath
	cur     int32
	max     int32
	label   string
	builtin bool
}

func kdeDisplays() ([]kdeDisplay, error) {
	b, err := sessionBus()
	if err != nil {
		return nil, err
	}
	if !b.hasName("org.kde.ScreenBrightness") {
		return nil, fmt.Errorf("PowerDevil brightness control is not running")
	}
	root := b.conn.Object("org.kde.ScreenBrightness", "/org/kde/ScreenBrightness")
	v, err := root.GetProperty("org.kde.ScreenBrightness.DisplaysDBusNames")
	if err != nil {
		return nil, err
	}
	names, _ := v.Value().([]string)
	var out []kdeDisplay
	for _, n := range names {
		p := dbus.ObjectPath("/org/kde/ScreenBrightness/" + n)
		o := b.conn.Object("org.kde.ScreenBrightness", p)
		d := kdeDisplay{path: p}
		if v, err := o.GetProperty("org.kde.ScreenBrightness.Display.Brightness"); err == nil {
			d.cur, _ = v.Value().(int32)
		}
		if v, err := o.GetProperty("org.kde.ScreenBrightness.Display.MaxBrightness"); err == nil {
			d.max, _ = v.Value().(int32)
		}
		if v, err := o.GetProperty("org.kde.ScreenBrightness.Display.IsInternal"); err == nil {
			d.builtin, _ = v.Value().(bool)
		}
		if d.max > 0 {
			out = append(out, d)
		}
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("no display with adjustable brightness")
	}
	for i, d := range out {
		if d.builtin && i > 0 {
			out[0], out[i] = out[i], out[0]
			break
		}
	}
	return out, nil
}

func brightnessctlInfo(c *setCtx) (int, error) {
	o, err := c.out("brightnessctl", "-m", "-c", "backlight", "info")
	if err != nil {
		return 0, fmt.Errorf("no backlight found")
	}
	f := strings.Split(strings.Split(o, "\n")[0], ",")
	if len(f) < 4 {
		return 0, fmt.Errorf("brightnessctl printed %q", o)
	}
	return strconv.Atoi(strings.TrimSuffix(f[3], "%"))
}

func getBrightness(c *setCtx) (any, error) {
	if desktopKind() == "kde" {
		if ds, err := kdeDisplays(); err == nil {
			return int(math.Round(float64(ds[0].cur) * 100 / float64(ds[0].max))), nil
		}
	}
	if lookPath("brightnessctl") != "" {
		n, err := brightnessctlInfo(c)
		if err != nil {
			return nil, err
		}
		return n, nil
	}
	return nil, fmt.Errorf("no display with adjustable brightness")
}

func setBrightness(c *setCtx, v any) error {
	pct := v.(int)
	if desktopKind() == "kde" {
		if ds, err := kdeDisplays(); err == nil {
			b, _ := sessionBus()
			val := int32(math.Round(float64(ds[0].max) * float64(pct) / 100))
			if val < 1 {
				val = 1
			}
			return b.conn.Object("org.kde.ScreenBrightness", ds[0].path).Call("org.kde.ScreenBrightness.Display.SetBrightness", 0, val, uint32(0)).Err
		}
	}
	if lookPath("brightnessctl") != "" {
		if _, err := brightnessctlInfo(c); err != nil {
			return err
		}
		return c.run(20*time.Second, "brightnessctl", "-q", "-c", "backlight", "set", strconv.Itoa(pct)+"%")
	}
	return fmt.Errorf("no display with adjustable brightness")
}

type outputScale struct {
	name  string
	scale float64
}

func outputs(c *setCtx) ([]outputScale, error) {
	var out []outputScale
	switch desktopKind() {
	case "kde":
		o, err := c.out("kscreen-doctor", "-j")
		if err != nil {
			return nil, err
		}
		var m struct {
			Outputs []struct {
				Name      string  `json:"name"`
				Enabled   bool    `json:"enabled"`
				Connected bool    `json:"connected"`
				Scale     float64 `json:"scale"`
			} `json:"outputs"`
		}
		if err := json.Unmarshal([]byte(o), &m); err != nil {
			return nil, fmt.Errorf("kscreen-doctor -j: %v", err)
		}
		for _, x := range m.Outputs {
			if x.Enabled && x.Connected {
				out = append(out, outputScale{x.Name, x.Scale})
			}
		}
	case "sway":
		o, err := c.out("swaymsg", "-t", "get_outputs", "-r")
		if err != nil {
			return nil, err
		}
		var m []struct {
			Name   string  `json:"name"`
			Active bool    `json:"active"`
			Scale  float64 `json:"scale"`
		}
		if err := json.Unmarshal([]byte(o), &m); err != nil {
			return nil, err
		}
		for _, x := range m {
			if x.Active {
				out = append(out, outputScale{x.Name, x.Scale})
			}
		}
	case "hyprland":
		o, err := c.out("hyprctl", "monitors", "-j")
		if err != nil {
			return nil, err
		}
		var m []struct {
			Name  string  `json:"name"`
			Scale float64 `json:"scale"`
		}
		if err := json.Unmarshal([]byte(o), &m); err != nil {
			return nil, err
		}
		for _, x := range m {
			out = append(out, outputScale{x.Name, x.Scale})
		}
	default:
		return nil, fmt.Errorf("not available on this desktop")
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("no active display")
	}
	return out, nil
}

var outputNameOK = func(n string) bool {
	if n == "" || len(n) > 64 {
		return false
	}
	for _, r := range n {
		if !(r == '-' || r == '_' || r == '.' || (r >= '0' && r <= '9') || (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z')) {
			return false
		}
	}
	return true
}

func getScale(c *setCtx) (any, error) {
	os, err := outputs(c)
	if err != nil {
		return nil, err
	}
	return math.Round(os[0].scale*100) / 100, nil
}

func setScale(c *setCtx, v any) error {
	f := v.(float64)
	os, err := outputs(c)
	if err != nil {
		return err
	}
	fs := strconv.FormatFloat(f, 'f', -1, 64)
	for _, o := range os {
		if !outputNameOK(o.name) {
			return fmt.Errorf("unexpected output name %q", o.name)
		}
		switch desktopKind() {
		case "kde":
			err = c.run(30*time.Second, "kscreen-doctor", "output."+o.name+".scale."+fs)
		case "sway":
			err = c.run(20*time.Second, "swaymsg", "output", o.name, "scale", fs)
		case "hyprland":
			err = c.run(20*time.Second, "hyprctl", "keyword", "monitor", o.name+",preferred,auto,"+fs)
		}
		if err != nil {
			return err
		}
	}
	return nil
}

var ppdNames = [][2]string{{"org.freedesktop.UPower.PowerProfiles", "/org/freedesktop/UPower/PowerProfiles"}, {"net.hadess.PowerProfiles", "/net/hadess/PowerProfiles"}}

func getPowerProfile(c *setCtx) (any, error) {
	for _, n := range ppdNames {
		if v, err := systemBusProp(n[0], n[1], n[0]+".ActiveProfile"); err == nil {
			s, _ := v.Value().(string)
			return s, nil
		}
	}
	if lookPath("powerprofilesctl") != "" {
		o, err := c.out("powerprofilesctl", "get")
		if err == nil {
			return strings.TrimSpace(o), nil
		}
	}
	return nil, fmt.Errorf("power-profiles-daemon is not running")
}

func setPowerProfile(c *setCtx, v any) error {
	want := v.(string)
	var lastErr error
	for _, n := range ppdNames {
		pv, err := systemBusProp(n[0], n[1], n[0]+".Profiles")
		if err != nil {
			lastErr = err
			continue
		}
		ok := false
		if list, _ := pv.Value().([]map[string]dbus.Variant); list != nil {
			for _, p := range list {
				if s, _ := p["Profile"].Value().(string); s == want {
					ok = true
				}
			}
		}
		if !ok {
			return fmt.Errorf("power.profile: %s is not supported on this hardware", want)
		}
		return systemBusSetProp(n[0], n[1], n[0]+".ActiveProfile", want)
	}
	if lookPath("powerprofilesctl") != "" {
		return c.run(20*time.Second, "powerprofilesctl", "set", want)
	}
	if lastErr != nil {
		return fmt.Errorf("power-profiles-daemon is not running: %v", lastErr)
	}
	return fmt.Errorf("power-profiles-daemon is not running")
}
