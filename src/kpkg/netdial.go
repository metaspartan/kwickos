package main

import (
	"crypto/rand"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"syscall"
	"time"
)

var (
	resolvConfPath = "/etc/resolv.conf"
	hostsPath      = "/etc/hosts"
	dnsPort        = 53
)

type ipAddr struct {
	ip   []byte
	zone string
}

func parseIPv4(s string) ([]byte, bool) {
	p := strings.Split(s, ".")
	if len(p) != 4 {
		return nil, false
	}
	ip := make([]byte, 4)
	for i, x := range p {
		n, err := strconv.Atoi(x)
		if err != nil || len(x) == 0 || len(x) > 3 || n > 255 || (len(x) > 1 && x[0] == '0') || x[0] == '+' || x[0] == '-' {
			return nil, false
		}
		ip[i] = byte(n)
	}
	return ip, true
}

func parseIPv6(s string) ([]byte, bool) {
	ip := make([]byte, 16)
	ell, i := -1, 0
	if strings.HasPrefix(s, "::") {
		ell, s = 0, s[2:]
	}
	for s != "" && i < 16 {
		j := 0
		for j < len(s) && j < 5 && s[j] != ':' && s[j] != '.' {
			j++
		}
		if j < len(s) && s[j] == '.' {
			v4, ok := parseIPv4(s)
			if !ok || i > 12 {
				return nil, false
			}
			copy(ip[i:], v4)
			i, s = i+4, ""
			break
		}
		n, err := strconv.ParseUint(s[:j], 16, 16)
		if err != nil || j == 0 || j > 4 {
			return nil, false
		}
		ip[i], ip[i+1] = byte(n>>8), byte(n)
		i, s = i+2, s[j:]
		if s == "" {
			break
		}
		s = s[1:]
		if strings.HasPrefix(s, ":") {
			if ell >= 0 {
				return nil, false
			}
			ell, s = i, s[1:]
		} else if s == "" {
			return nil, false
		}
	}
	if s != "" {
		return nil, false
	}
	if i < 16 {
		if ell < 0 {
			return nil, false
		}
		n := 16 - i
		copy(ip[ell+n:], ip[ell:i])
		clear(ip[ell : ell+n])
	} else if ell >= 0 {
		return nil, false
	}
	return ip, true
}

func parseIP(s string) (ipAddr, bool) {
	if ip, ok := parseIPv4(s); ok {
		return ipAddr{ip: ip}, true
	}
	h, zone, _ := strings.Cut(s, "%")
	if !strings.Contains(h, ":") {
		return ipAddr{}, false
	}
	ip, ok := parseIPv6(h)
	return ipAddr{ip: ip, zone: zone}, ok
}

func (a ipAddr) sockaddr(port int) (int, syscall.Sockaddr) {
	if len(a.ip) == 4 {
		sa := &syscall.SockaddrInet4{Port: port}
		copy(sa.Addr[:], a.ip)
		return syscall.AF_INET, sa
	}
	sa := &syscall.SockaddrInet6{Port: port}
	copy(sa.Addr[:], a.ip)
	if a.zone != "" {
		n, err := strconv.Atoi(a.zone)
		if err != nil {
			b, _ := os.ReadFile("/sys/class/net/" + a.zone + "/ifindex")
			n, _ = strconv.Atoi(strings.TrimSpace(string(b)))
		}
		sa.ZoneId = uint32(n)
	}
	return syscall.AF_INET6, sa
}

func sockConnect(a ipAddr, port, typ int, deadline time.Time) (*os.File, error) {
	fam, sa := a.sockaddr(port)
	fd, err := syscall.Socket(fam, typ|syscall.SOCK_NONBLOCK|syscall.SOCK_CLOEXEC, 0)
	if err != nil {
		return nil, os.NewSyscallError("socket", err)
	}
	if typ == syscall.SOCK_STREAM {
		syscall.SetsockoptInt(fd, syscall.IPPROTO_TCP, syscall.TCP_NODELAY, 1)
	}
	err = syscall.Connect(fd, sa)
	if err != nil && err != syscall.EINPROGRESS && err != syscall.EINTR {
		syscall.Close(fd)
		return nil, os.NewSyscallError("connect", err)
	}
	f := os.NewFile(uintptr(fd), "socket")
	if err == nil {
		return f, nil
	}
	rc, err := f.SyscallConn()
	if err != nil {
		f.Close()
		return nil, err
	}
	f.SetWriteDeadline(deadline)
	var cerr error
	err = rc.Write(func(fd uintptr) bool {
		v, e := syscall.GetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_ERROR)
		if e != nil {
			cerr = e
			return true
		}
		switch e := syscall.Errno(v); e {
		case syscall.EINPROGRESS, syscall.EALREADY, syscall.EINTR:
			return false
		case 0, syscall.EISCONN:
			_, pe := syscall.Getpeername(int(fd))
			return pe == nil
		default:
			cerr = os.NewSyscallError("connect", e)
			return true
		}
	})
	if err == nil {
		err = cerr
	}
	if err != nil {
		f.Close()
		return nil, err
	}
	f.SetWriteDeadline(time.Time{})
	return f, nil
}

func splitHostPort(addr string) (string, int, error) {
	var host, port string
	if strings.HasPrefix(addr, "[") {
		i := strings.Index(addr, "]:")
		if i < 0 {
			return "", 0, fmt.Errorf("address %s: missing port", addr)
		}
		host, port = addr[1:i], addr[i+2:]
	} else {
		i := strings.LastIndexByte(addr, ':')
		if i < 0 || strings.Contains(addr[:i], ":") {
			return "", 0, fmt.Errorf("address %s: missing port or too many colons", addr)
		}
		host, port = addr[:i], addr[i+1:]
	}
	n, err := strconv.Atoi(port)
	if err != nil || n < 0 || n > 65535 {
		return "", 0, fmt.Errorf("address %s: invalid port", addr)
	}
	return host, n, nil
}

func dialTCP(addr string, timeout time.Duration) (*os.File, error) {
	host, port, err := splitHostPort(addr)
	if err != nil {
		return nil, err
	}
	deadline := time.Now().Add(timeout)
	ips, err := lookupHost(host)
	if err != nil {
		return nil, fmt.Errorf("dial tcp %s: %v", addr, err)
	}
	type result struct {
		f   *os.File
		err error
	}
	ch := make(chan result, len(ips))
	next, pending := 0, 0
	start := func() {
		a := ips[next]
		next++
		pending++
		go func() {
			f, err := sockConnect(a, port, syscall.SOCK_STREAM, deadline)
			ch <- result{f, err}
		}()
	}
	start()
	timer := time.NewTimer(300 * time.Millisecond)
	defer timer.Stop()
	var firstErr error
	for pending > 0 {
		select {
		case r := <-ch:
			pending--
			if r.err == nil {
				go func(n int) {
					for ; n > 0; n-- {
						if x := <-ch; x.f != nil {
							x.f.Close()
						}
					}
				}(pending)
				return r.f, nil
			}
			if firstErr == nil {
				firstErr = r.err
			}
			if next < len(ips) {
				start()
				timer.Reset(300 * time.Millisecond)
			}
		case <-timer.C:
			if next < len(ips) {
				start()
				timer.Reset(300 * time.Millisecond)
			}
		}
	}
	return nil, fmt.Errorf("dial tcp %s: %v", addr, firstErr)
}

type dnsConf struct {
	servers  []ipAddr
	search   []string
	ndots    int
	attempts int
	timeout  time.Duration
	tcp      bool
}

func fqdn(s string) string {
	if strings.HasSuffix(s, ".") {
		return s
	}
	return s + "."
}

func readDNSConf() *dnsConf {
	c := &dnsConf{ndots: 1, attempts: 2, timeout: 5 * time.Second}
	data, _ := os.ReadFile(resolvConfPath)
	for _, line := range strings.Split(string(data), "\n") {
		if i := strings.IndexAny(line, "#;"); i >= 0 {
			line = line[:i]
		}
		f := strings.Fields(line)
		if len(f) < 2 {
			continue
		}
		switch f[0] {
		case "nameserver":
			if a, ok := parseIP(f[1]); ok && len(c.servers) < 3 {
				c.servers = append(c.servers, a)
			}
		case "domain":
			c.search = []string{fqdn(f[1])}
		case "search":
			c.search = c.search[:0]
			for _, d := range f[1:] {
				if d != "." {
					c.search = append(c.search, fqdn(d))
				}
			}
		case "options":
			for _, o := range f[1:] {
				k, v, _ := strings.Cut(o, ":")
				n, _ := strconv.Atoi(v)
				switch k {
				case "ndots":
					c.ndots = min(max(n, 0), 15)
				case "timeout":
					c.timeout = time.Duration(max(n, 1)) * time.Second
				case "attempts":
					c.attempts = min(max(n, 1), 5)
				case "use-vc", "usevc", "tcp":
					c.tcp = true
				}
			}
		}
	}
	if len(c.servers) == 0 {
		c.servers = []ipAddr{{ip: []byte{127, 0, 0, 1}}, {ip: append(make([]byte, 15), 1)}}
	}
	if c.search == nil {
		if h, err := os.Hostname(); err == nil {
			if i := strings.IndexByte(h, '.'); i >= 0 && i < len(h)-1 {
				c.search = []string{fqdn(h[i+1:])}
			}
		}
	}
	return c
}

func hostsLookup(name string) []ipAddr {
	data, _ := os.ReadFile(hostsPath)
	name = strings.TrimSuffix(name, ".")
	var out []ipAddr
	for _, line := range strings.Split(string(data), "\n") {
		if i := strings.IndexByte(line, '#'); i >= 0 {
			line = line[:i]
		}
		f := strings.Fields(line)
		if len(f) < 2 {
			continue
		}
		a, ok := parseIP(f[0])
		if !ok {
			continue
		}
		for _, h := range f[1:] {
			if strings.EqualFold(strings.TrimSuffix(h, "."), name) {
				out = append(out, a)
				break
			}
		}
	}
	return out
}

func (c *dnsConf) names(host string) []string {
	if strings.HasSuffix(host, ".") {
		return []string{host}
	}
	abs := strings.Count(host, ".") >= c.ndots
	var out []string
	if abs {
		out = append(out, host+".")
	}
	for _, s := range c.search {
		if len(host)+len(s) <= 254 {
			out = append(out, host+"."+s)
		}
	}
	if !abs {
		out = append(out, host+".")
	}
	return out
}

func lookupHost(host string) ([]ipAddr, error) {
	if a, ok := parseIP(host); ok {
		return []ipAddr{a}, nil
	}
	if host == "" || len(host) > 253 {
		return nil, fmt.Errorf("lookup %q: invalid host name", host)
	}
	if ips := hostsLookup(host); len(ips) > 0 {
		return ips, nil
	}
	c := readDNSConf()
	var lastErr error
	for _, n := range c.names(host) {
		ips, err := c.lookupName(n)
		if len(ips) > 0 {
			return ips, nil
		}
		if err != nil {
			lastErr = err
		}
	}
	if lastErr == nil {
		lastErr = errors.New("no such host")
	}
	return nil, fmt.Errorf("lookup %s: %v", host, lastErr)
}

func (c *dnsConf) lookupName(name string) ([]ipAddr, error) {
	type res struct {
		ips []ipAddr
		err error
	}
	ch := make(chan res, 1)
	go func() {
		ips, err := c.query(name, 28)
		ch <- res{ips, err}
	}()
	v4, err := c.query(name, 1)
	r := <-ch
	ips := append(v4, r.ips...)
	if len(ips) > 0 {
		return ips, nil
	}
	if err == nil {
		err = r.err
	}
	return nil, err
}

var errNXDomain = errors.New("no such host")

func (c *dnsConf) query(name string, qtype uint16) ([]ipAddr, error) {
	q, ok := dnsQuery(name, qtype)
	if !ok {
		return nil, errors.New("invalid host name")
	}
	var lastErr error
	for a := 0; a < c.attempts; a++ {
		for _, s := range c.servers {
			var idb [2]byte
			rand.Read(idb[:])
			q[0], q[1] = idb[0], idb[1]
			resp, err := dnsExchange(s, q, c.timeout, c.tcp)
			if err == nil && resp[2]&2 != 0 && !c.tcp {
				resp, err = dnsExchange(s, q, c.timeout, true)
			}
			if err != nil {
				lastErr = err
				continue
			}
			ips, rcode, ok := dnsParse(resp, q, name, qtype)
			switch {
			case !ok:
				lastErr = errors.New("malformed DNS response")
			case rcode == 3:
				return nil, errNXDomain
			case rcode == 0:
				return ips, nil
			default:
				lastErr = fmt.Errorf("server misbehaving (rcode %d)", rcode)
			}
		}
	}
	return nil, lastErr
}

func dnsQuery(name string, qtype uint16) ([]byte, bool) {
	b := []byte{0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0}
	for _, l := range strings.Split(strings.TrimSuffix(name, "."), ".") {
		if len(l) == 0 || len(l) > 63 {
			return nil, false
		}
		b = append(b, byte(len(l)))
		b = append(b, l...)
	}
	return append(b, 0, byte(qtype>>8), byte(qtype), 0, 1), len(b) <= 12+255
}

func dnsExchange(s ipAddr, q []byte, timeout time.Duration, tcp bool) ([]byte, error) {
	deadline := time.Now().Add(timeout)
	typ := syscall.SOCK_DGRAM
	if tcp {
		typ = syscall.SOCK_STREAM
	}
	f, err := sockConnect(s, dnsPort, typ, deadline)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	f.SetDeadline(deadline)
	if tcp {
		if _, err := f.Write(append([]byte{byte(len(q) >> 8), byte(len(q))}, q...)); err != nil {
			return nil, err
		}
		var l [2]byte
		if _, err := io.ReadFull(f, l[:]); err != nil {
			return nil, err
		}
		resp := make([]byte, binary.BigEndian.Uint16(l[:]))
		if _, err := io.ReadFull(f, resp); err != nil {
			return nil, err
		}
		if len(resp) < 12 || resp[0] != q[0] || resp[1] != q[1] {
			return nil, errors.New("malformed DNS response")
		}
		return resp, nil
	}
	if _, err := f.Write(q); err != nil {
		return nil, err
	}
	buf := make([]byte, 1500)
	for {
		n, err := f.Read(buf)
		if err != nil {
			return nil, err
		}
		if n >= 12 && buf[0] == q[0] && buf[1] == q[1] && buf[2]&0x80 != 0 {
			return buf[:n], nil
		}
	}
}

func dnsName(msg []byte, off int) (string, int, bool) {
	var sb strings.Builder
	end, jumps := -1, 0
	for {
		if off >= len(msg) {
			return "", 0, false
		}
		c := int(msg[off])
		switch {
		case c == 0:
			if end < 0 {
				end = off + 1
			}
			if sb.Len() == 0 {
				sb.WriteByte('.')
			}
			return sb.String(), end, sb.Len() <= 255
		case c&0xc0 == 0xc0:
			if off+1 >= len(msg) || jumps > 64 {
				return "", 0, false
			}
			if end < 0 {
				end = off + 2
			}
			off = (c&0x3f)<<8 | int(msg[off+1])
			jumps++
		case c&0xc0 == 0:
			if off+1+c > len(msg) {
				return "", 0, false
			}
			sb.WriteString(strings.ToLower(string(msg[off+1 : off+1+c])))
			sb.WriteByte('.')
			off += 1 + c
		default:
			return "", 0, false
		}
	}
}

func dnsParse(msg, q []byte, name string, qtype uint16) ([]ipAddr, int, bool) {
	if len(msg) < 12 || msg[0] != q[0] || msg[1] != q[1] || msg[2]&0x80 == 0 {
		return nil, 0, false
	}
	rcode := int(msg[3] & 0xf)
	qd, an := int(binary.BigEndian.Uint16(msg[4:])), int(binary.BigEndian.Uint16(msg[6:]))
	name = strings.ToLower(fqdn(name))
	off := 12
	for i := 0; i < qd; i++ {
		n, o, ok := dnsName(msg, off)
		if !ok || o+4 > len(msg) || (i == 0 && (n != name || binary.BigEndian.Uint16(msg[o:]) != qtype)) {
			return nil, 0, false
		}
		off = o + 4
	}
	type rr struct {
		name, target string
		typ          uint16
		data         []byte
	}
	var rrs []rr
	for i := 0; i < an; i++ {
		n, o, ok := dnsName(msg, off)
		if !ok || o+10 > len(msg) {
			return nil, 0, false
		}
		typ, l := binary.BigEndian.Uint16(msg[o:]), int(binary.BigEndian.Uint16(msg[o+8:]))
		if o+10+l > len(msg) {
			return nil, 0, false
		}
		r := rr{name: n, typ: typ, data: msg[o+10 : o+10+l]}
		if typ == 5 {
			if r.target, _, ok = dnsName(msg, o+10); !ok {
				return nil, 0, false
			}
		}
		rrs = append(rrs, r)
		off = o + 10 + l
	}
	cur := name
	for hop := 0; hop < 16; hop++ {
		moved := false
		for _, r := range rrs {
			if r.typ == 5 && r.name == cur {
				cur, moved = r.target, true
				break
			}
		}
		if !moved {
			break
		}
	}
	var ips []ipAddr
	for _, r := range rrs {
		if r.typ == qtype && r.name == cur && (qtype == 1 && len(r.data) == 4 || qtype == 28 && len(r.data) == 16) {
			ips = append(ips, ipAddr{ip: append([]byte(nil), r.data...)})
		}
	}
	return ips, rcode, true
}
