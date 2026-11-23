package main

import (
	"bytes"
	"context"
	"fmt"
	"image"
	"image/draw"
	"image/jpeg"
	"image/png"
	"io"
	"math"
	"os"
	"time"

	"github.com/godbus/dbus/v5"
)

type shotGeom struct {
	OriginX float64 `json:"origin_x"`
	OriginY float64 `json:"origin_y"`
	Scale   float64 `json:"scale"`
	Width   int     `json:"width"`
	Height  int     `json:"height"`
}

func (g shotGeom) toScreen(x, y float64) (float64, float64) {
	return g.OriginX + x*g.Scale, g.OriginY + y*g.Scale
}

func (g shotGeom) fromScreen(x, y float64) (float64, float64) {
	return (x - g.OriginX) / g.Scale, (y - g.OriginY) / g.Scale
}

type rectF struct{ X, Y, W, H float64 }

func rawToRGBA(data []byte, w, h, stride int, format uint32) (*image.RGBA, error) {
	if w <= 0 || h <= 0 || w > 32768 || h > 32768 || stride < w {
		return nil, fmt.Errorf("bad image size %dx%d stride %d", w, h, stride)
	}
	bpp := 4
	switch format {
	case 13, 29:
		bpp = 3
	case 4, 5, 6, 16, 17, 18:
	default:
		return nil, fmt.Errorf("unsupported image format %d", format)
	}
	if stride < w*bpp || len(data) < stride*(h-1)+w*bpp {
		return nil, fmt.Errorf("image data too short (%d bytes for %dx%d)", len(data), w, h)
	}
	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		row := data[y*stride:]
		out := dst.Pix[y*dst.Stride:]
		for x := 0; x < w; x++ {
			p := row[x*bpp:]
			o := out[x*4 : x*4+4]
			switch format {
			case 4, 5, 6, 29:
				o[0], o[1], o[2], o[3] = p[2], p[1], p[0], 255
			default:
				o[0], o[1], o[2], o[3] = p[0], p[1], p[2], 255
			}
		}
	}
	return dst, nil
}

func kwinScreenshot() (image.Image, error) {
	b, err := sessionBus()
	if err != nil {
		return nil, err
	}
	if !b.hasName("org.kde.KWin") {
		return nil, fmt.Errorf("KWin is not running")
	}
	r, w, err := os.Pipe()
	if err != nil {
		return nil, err
	}
	defer r.Close()
	type res struct {
		data []byte
		err  error
	}
	ch := make(chan res, 1)
	go func() {
		d, err := io.ReadAll(io.LimitReader(r, 512<<20))
		ch <- res{d, err}
	}()
	opts := map[string]dbus.Variant{"include-cursor": dbus.MakeVariant(false), "native-resolution": dbus.MakeVariant(true)}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	call := b.conn.Object("org.kde.KWin", "/org/kde/KWin/ScreenShot2").CallWithContext(ctx, "org.kde.KWin.ScreenShot2.CaptureWorkspace", 0, opts, dbus.UnixFD(w.Fd()))
	w.Close()
	if call.Err != nil {
		return nil, call.Err
	}
	var meta map[string]dbus.Variant
	if err := call.Store(&meta); err != nil {
		return nil, err
	}
	var rr res
	select {
	case rr = <-ch:
	case <-time.After(20 * time.Second):
		return nil, fmt.Errorf("KWin did not send the image")
	}
	if rr.err != nil {
		return nil, rr.err
	}
	u := func(k string) uint32 {
		switch v := meta[k].Value().(type) {
		case uint32:
			return v
		case int32:
			return uint32(v)
		case uint64:
			return uint32(v)
		case int64:
			return uint32(v)
		}
		return 0
	}
	if t, _ := meta["type"].Value().(string); t != "" && t != "raw" {
		return nil, fmt.Errorf("KWin sent a %s image", t)
	}
	return rawToRGBA(rr.data, int(u("width")), int(u("height")), int(u("stride")), u("format"))
}

func toRGBA(src image.Image) *image.RGBA {
	if r, ok := src.(*image.RGBA); ok && r.Rect.Min == (image.Point{}) {
		return r
	}
	b := src.Bounds()
	dst := image.NewRGBA(image.Rect(0, 0, b.Dx(), b.Dy()))
	draw.Draw(dst, dst.Bounds(), src, b.Min, draw.Src)
	return dst
}

func cropRGBA(src *image.RGBA, r image.Rectangle) *image.RGBA {
	r = r.Intersect(src.Bounds())
	dst := image.NewRGBA(image.Rect(0, 0, r.Dx(), r.Dy()))
	draw.Draw(dst, dst.Bounds(), src, r.Min, draw.Src)
	return dst
}

func downscale(src *image.RGBA, w, h int) *image.RGBA {
	sw, sh := src.Rect.Dx(), src.Rect.Dy()
	if w >= sw && h >= sh {
		return src
	}
	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	fx := float64(sw) / float64(w)
	fy := float64(sh) / float64(h)
	for y := 0; y < h; y++ {
		y0 := float64(y) * fy
		y1 := y0 + fy
		iy0, iy1 := int(y0), int(math.Ceil(y1))
		if iy1 > sh {
			iy1 = sh
		}
		for x := 0; x < w; x++ {
			x0 := float64(x) * fx
			x1 := x0 + fx
			ix0, ix1 := int(x0), int(math.Ceil(x1))
			if ix1 > sw {
				ix1 = sw
			}
			var r, g, b, a, wt float64
			for sy := iy0; sy < iy1; sy++ {
				wy := math.Min(y1, float64(sy+1)) - math.Max(y0, float64(sy))
				if wy <= 0 {
					continue
				}
				row := src.Pix[sy*src.Stride:]
				for sx := ix0; sx < ix1; sx++ {
					wx := math.Min(x1, float64(sx+1)) - math.Max(x0, float64(sx))
					if wx <= 0 {
						continue
					}
					ww := wx * wy
					p := row[sx*4 : sx*4+4]
					r += float64(p[0]) * ww
					g += float64(p[1]) * ww
					b += float64(p[2]) * ww
					a += float64(p[3]) * ww
					wt += ww
				}
			}
			o := dst.Pix[y*dst.Stride+x*4:]
			if wt > 0 {
				o[0] = uint8(r/wt + 0.5)
				o[1] = uint8(g/wt + 0.5)
				o[2] = uint8(b/wt + 0.5)
				o[3] = uint8(a/wt + 0.5)
			}
		}
	}
	return dst
}

func fitSize(w, h, maxW, maxH int) (int, int) {
	if w <= maxW && h <= maxH {
		return w, h
	}
	f := math.Min(float64(maxW)/float64(w), float64(maxH)/float64(h))
	nw, nh := int(math.Round(float64(w)*f)), int(math.Round(float64(h)*f))
	if nw < 1 {
		nw = 1
	}
	if nh < 1 {
		nh = 1
	}
	return nw, nh
}

func processShot(src image.Image, desk rectF, region *rectF, maxW, maxH int, format string, quality int) ([]byte, string, shotGeom, error) {
	if src == nil || src.Bounds().Empty() {
		return nil, "", shotGeom{}, fmt.Errorf("the screenshot is empty")
	}
	var err error
	img := toRGBA(src)
	iw, ih := img.Rect.Dx(), img.Rect.Dy()
	if desk.W <= 0 || desk.H <= 0 {
		desk = rectF{0, 0, float64(iw), float64(ih)}
	}
	px := float64(iw) / desk.W
	origin := [2]float64{desk.X, desk.Y}
	if region != nil {
		if region.W < 1 || region.H < 1 {
			return nil, "", shotGeom{}, fmt.Errorf("region width and height must be at least 1")
		}
		r := image.Rect(int(math.Floor((region.X-desk.X)*px)), int(math.Floor((region.Y-desk.Y)*px)),
			int(math.Ceil((region.X-desk.X+region.W)*px)), int(math.Ceil((region.Y-desk.Y+region.H)*px)))
		if r.Intersect(img.Bounds()).Empty() {
			return nil, "", shotGeom{}, fmt.Errorf("the region is outside the screen (%.0fx%.0f at %.0f,%.0f)", desk.W, desk.H, desk.X, desk.Y)
		}
		r = r.Intersect(img.Bounds())
		img = cropRGBA(img, r)
		origin = [2]float64{desk.X + float64(r.Min.X)/px, desk.Y + float64(r.Min.Y)/px}
	}
	cw, chh := img.Rect.Dx(), img.Rect.Dy()
	nw, nh := fitSize(cw, chh, maxW, maxH)
	img = downscale(img, nw, nh)
	g := shotGeom{OriginX: origin[0], OriginY: origin[1], Scale: float64(cw) / px / float64(nw), Width: nw, Height: nh}
	var buf bytes.Buffer
	mime := "image/png"
	switch format {
	case "jpeg", "jpg":
		mime = "image/jpeg"
		if quality <= 0 || quality > 100 {
			quality = 85
		}
		err = jpeg.Encode(&buf, img, &jpeg.Options{Quality: quality})
	default:
		err = (&png.Encoder{CompressionLevel: png.BestSpeed}).Encode(&buf, img)
	}
	if err != nil {
		return nil, "", shotGeom{}, err
	}
	return buf.Bytes(), mime, g, nil
}
