package main

import (
	"encoding/binary"
	"io"
	"net"
	"net/netip"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestParseIP(t *testing.T) {
	for _, s := range []string{"1.2.3.4", "0.0.0.0", "255.255.255.255", "::", "::1", "1::", "fe80::1", "2001:db8::8:800:200c:417a", "1:2:3:4:5:6:7:8", "::ffff:1.2.3.4", "64:ff9b::192.0.2.33", "1:2:3:4:5:6:1.2.3.4", "fe80::1%eth0", "1.2.3", "1.2.3.4.5", "01.2.3.4", "256.1.1.1", "1:2:3:4:5:6:7", "1:2:3:4:5:6:7:8:9", "1::2::3", ":1", "1:", "12345::", "1:2:3:4:5:6:7::8", "::1.2.3", "g::", "", "1.2.3.-4", "1:2:3:4:5:6:7:1.2.3.4"} {
		want, err := netip.ParseAddr(s)
		got, ok := parseIP(s)
		if ok != (err == nil) {
			t.Errorf("%q: ok=%v, netip err=%v", s, ok, err)
			continue
		}
		if ok && (string(got.ip) != string(want.AsSlice()) || got.zone != want.Zone()) {
			t.Errorf("%q: got %v %q, want %v", s, got.ip, got.zone, want)
		}
	}
}

type fakeDNS struct {
	answers map[string][][]byte
	cname   map[string]string
	trunc   bool
	queries atomic.Int32
}

func dnsNameBytes(n string) []byte {
	var b []byte
	for _, l := range strings.Split(strings.TrimSuffix(n, "."), ".") {
		b = append(b, byte(len(l)))
		b = append(b, l...)
	}
	return append(b, 0)
}

func (d *fakeDNS) reply(q []byte, tcp bool) []byte {
	d.queries.Add(1)
	name, off, _ := dnsName(q, 12)
	qtype := binary.BigEndian.Uint16(q[off:])
	r := append([]byte(nil), q[:off+4]...)
	r[2], r[3] = 0x81, 0x80
	var an [][]byte
	cur := name
	if c, ok := d.cname[cur]; ok {
		rec := append([]byte{0xc0, 12, 0, 5, 0, 1, 0, 0, 0, 60}, 0, 0)
		cn := dnsNameBytes(c)
		binary.BigEndian.PutUint16(rec[10:], uint16(len(cn)))
		an = append(an, append(rec, cn...))
		cur = c
	}
	ips, ok := d.answers[cur]
	if !ok && cur == name {
		r[3] = 0x83
	}
	for _, ip := range ips {
		if (qtype == 1) != (len(ip) == 4) {
			continue
		}
		rec := append(dnsNameBytes(cur), byte(qtype>>8), byte(qtype), 0, 1, 0, 0, 0, 60, 0, byte(len(ip)))
		an = append(an, append(rec, ip...))
	}
	if d.trunc && !tcp {
		r[2] |= 2
		an = nil
	}
	binary.BigEndian.PutUint16(r[6:], uint16(len(an)))
	for _, a := range an {
		r = append(r, a...)
	}
	return r
}

func startFakeDNS(t *testing.T, d *fakeDNS) int {
	pc, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := pc.LocalAddr().(*net.UDPAddr).Port
	ln, err := net.Listen("tcp4", "127.0.0.1:"+strconv.Itoa(port))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { pc.Close(); ln.Close() })
	go func() {
		buf := make([]byte, 1500)
		for {
			n, a, err := pc.ReadFrom(buf)
			if err != nil {
				return
			}
			pc.WriteTo(d.reply(buf[:n], false), a)
		}
	}()
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			var l [2]byte
			io.ReadFull(c, l[:])
			q := make([]byte, binary.BigEndian.Uint16(l[:]))
			io.ReadFull(c, q)
			r := d.reply(q, true)
			c.Write(append([]byte{byte(len(r) >> 8), byte(len(r))}, r...))
			c.Close()
		}
	}()
	return port
}

func withResolver(t *testing.T, conf, hosts string, port int) {
	dir := t.TempDir()
	oc, oh, op := resolvConfPath, hostsPath, dnsPort
	resolvConfPath, hostsPath, dnsPort = filepath.Join(dir, "resolv.conf"), filepath.Join(dir, "hosts"), port
	t.Cleanup(func() { resolvConfPath, hostsPath, dnsPort = oc, oh, op })
	os.WriteFile(resolvConfPath, []byte(conf), 0644)
	os.WriteFile(hostsPath, []byte(hosts), 0644)
}

func ipStrings(ips []ipAddr) string {
	var s []string
	for _, a := range ips {
		x, _ := netip.AddrFromSlice(a.ip)
		s = append(s, x.String())
	}
	return strings.Join(s, ",")
}

func TestResolver(t *testing.T) {
	d := &fakeDNS{
		answers: map[string][][]byte{
			"deb.example.":           {{192, 0, 2, 1}, {192, 0, 2, 2}, net.ParseIP("2001:db8::1")},
			"cdn.example.":           {{198, 51, 100, 7}},
			"mirror.corp.example.":   {{203, 0, 113, 9}},
			"v6only.example.":        {net.ParseIP("2001:db8::6")},
			"shortname.lan.example.": {{203, 0, 113, 10}},
		},
		cname: map[string]string{"deb.alias.": "cdn.example."},
	}
	port := startFakeDNS(t, d)
	withResolver(t, "# c\nnameserver 127.0.0.1\nsearch corp.example lan.example\noptions ndots:1 timeout:2 attempts:1\n", "127.0.0.1 localhost\n10.1.2.3 pinned.example pinned\n::1 ip6-localhost\n", port)
	cases := map[string]string{
		"deb.example":    "192.0.2.1,192.0.2.2,2001:db8::1",
		"deb.alias":      "198.51.100.7",
		"mirror":         "203.0.113.9",
		"shortname":      "203.0.113.10",
		"v6only.example": "2001:db8::6",
		"PINNED":         "10.1.2.3",
		"localhost":      "127.0.0.1",
		"192.0.2.55":     "192.0.2.55",
		"2001:db8::99":   "2001:db8::99",
	}
	for host, want := range cases {
		ips, err := lookupHost(host)
		if err != nil || ipStrings(ips) != want {
			t.Errorf("%s: got %s %v, want %s", host, ipStrings(ips), err, want)
		}
	}
	if _, err := lookupHost("nonexistent.example"); err == nil || !strings.Contains(err.Error(), "no such host") {
		t.Errorf("nonexistent: %v", err)
	}
	d.trunc = true
	if ips, err := lookupHost("cdn.example"); err != nil || ipStrings(ips) != "198.51.100.7" {
		t.Errorf("tcp fallback: %s %v", ipStrings(ips), err)
	}
}

func TestResolverTimeout(t *testing.T) {
	pc, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer pc.Close()
	withResolver(t, "nameserver 127.0.0.1\noptions timeout:1 attempts:1\n", "", pc.LocalAddr().(*net.UDPAddr).Port)
	s := time.Now()
	if _, err := lookupHost("silent.example."); err == nil {
		t.Fatal("lookup against a silent server succeeded")
	}
	if d := time.Since(s); d > 4*time.Second {
		t.Fatalf("timeout took %v", d)
	}
}

func TestDNSParseRejectsGarbage(t *testing.T) {
	q, _ := dnsQuery("a.example.", 1)
	for i := 0; i < 2000; i++ {
		m := make([]byte, i%300)
		for j := range m {
			m[j] = byte(i*31 + j*7)
		}
		if len(m) > 2 {
			m[0], m[1] = q[0], q[1]
		}
		dnsParse(m, q, "a.example.", 1)
	}
	loop := append(append([]byte(nil), q[:12]...), 0xc0, 12, 0, 1, 0, 1)
	loop[2] = 0x81
	if _, _, ok := dnsParse(loop, q, "a.example.", 1); ok {
		t.Fatal("pointer loop accepted")
	}
}

func TestDialTCP(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func() {
				io.Copy(c, c)
				c.Close()
			}()
		}
	}()
	port := ln.Addr().(*net.TCPAddr).Port
	withResolver(t, "nameserver 127.0.0.1\n", "192.0.2.1 blackhole.test\n127.0.0.1 blackhole.test\n", 1)
	for _, addr := range []string{"127.0.0.1:" + strconv.Itoa(port), "blackhole.test:" + strconv.Itoa(port)} {
		s := time.Now()
		c, err := dialTCP(addr, 5*time.Second)
		if err != nil {
			t.Fatalf("%s: %v", addr, err)
		}
		if d := time.Since(s); d > 2*time.Second {
			t.Errorf("%s: dial took %v", addr, d)
		}
		c.SetReadDeadline(time.Now().Add(2 * time.Second))
		c.Write([]byte("ping"))
		buf := make([]byte, 4)
		if _, err := io.ReadFull(c, buf); err != nil || string(buf) != "ping" {
			t.Fatalf("%s: echo %q %v", addr, buf, err)
		}
		c.Close()
	}
	ln2, _ := net.Listen("tcp", "127.0.0.1:0")
	dead := ln2.Addr().String()
	ln2.Close()
	if _, err := dialTCP(dead, 2*time.Second); err == nil || !strings.Contains(err.Error(), "refused") {
		t.Fatalf("closed port: %v", err)
	}
	if ln6, err := net.Listen("tcp6", "[::1]:0"); err == nil {
		go func() {
			if c, err := ln6.Accept(); err == nil {
				c.Write([]byte("v6"))
				c.Close()
			}
		}()
		c, err := dialTCP(ln6.Addr().String(), 2*time.Second)
		if err != nil {
			t.Fatalf("ipv6 dial: %v", err)
		}
		b, _ := io.ReadAll(c)
		c.Close()
		ln6.Close()
		if string(b) != "v6" {
			t.Fatalf("ipv6 read %q", b)
		}
	}
	for _, bad := range []string{"noport", "a:b:c", "host:99999", "[::1]"} {
		if _, err := dialTCP(bad, time.Second); err == nil {
			t.Errorf("%q accepted", bad)
		}
	}
}
