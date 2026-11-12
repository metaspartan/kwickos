package main

// A deliberately tiny HTTP/1.1 client. Debian-style repositories do not
// need TLS for integrity (InRelease signatures + SHA256 of every file), and
// dropping net/http + crypto/tls shrinks kpkg by ~3.5 MB. https:// sources
// are fetched through wget/curl when present (also verified by signature).

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"
)

type httpResp struct {
	Body io.ReadCloser
	Code int
}

type hconn struct {
	c  net.Conn
	br *bufio.Reader
}

var connPool = struct {
	sync.Mutex
	m map[string][]*hconn
}{m: map[string][]*hconn{}}

func getConn(addr string) (*hconn, error) {
	connPool.Lock()
	if l := connPool.m[addr]; len(l) > 0 {
		c := l[len(l)-1]
		connPool.m[addr] = l[:len(l)-1]
		connPool.Unlock()
		return c, nil
	}
	connPool.Unlock()
	c, err := net.DialTimeout("tcp", addr, 20*time.Second)
	if err != nil {
		return nil, err
	}
	return &hconn{c: c, br: bufio.NewReaderSize(c, 64<<10)}, nil
}

func putConn(addr string, c *hconn) {
	connPool.Lock()
	connPool.m[addr] = append(connPool.m[addr], c)
	connPool.Unlock()
}

type deadlineReader struct{ c net.Conn; r io.Reader }

func (d *deadlineReader) Read(p []byte) (int, error) {
	d.c.SetReadDeadline(time.Now().Add(60 * time.Second))
	return d.r.Read(p)
}

type body struct {
	r      io.Reader
	hc     *hconn
	addr   string
	reuse  bool
	done   bool
	closed bool
}

func (b *body) Read(p []byte) (int, error) {
	n, err := b.r.Read(p)
	if err == io.EOF {
		b.done = true
	}
	return n, err
}

func (b *body) Close() error {
	if b.closed {
		return nil
	}
	b.closed = true
	if b.done && b.reuse {
		putConn(b.addr, b.hc)
		return nil
	}
	return b.hc.c.Close()
}

type chunked struct {
	br  *bufio.Reader
	n   int64
	eof bool
}

func (c *chunked) Read(p []byte) (int, error) {
	if c.eof {
		return 0, io.EOF
	}
	if c.n == 0 {
		line, err := c.br.ReadString('\n')
		if err != nil {
			return 0, err
		}
		line = strings.TrimSpace(line)
		if i := strings.IndexByte(line, ';'); i >= 0 {
			line = line[:i]
		}
		n, err := strconv.ParseInt(line, 16, 64)
		if err != nil {
			return 0, errors.New("bad chunk size")
		}
		if n == 0 {
			for { // trailers
				l, err := c.br.ReadString('\n')
				if err != nil || strings.TrimSpace(l) == "" {
					break
				}
			}
			c.eof = true
			return 0, io.EOF
		}
		c.n = n
	}
	if int64(len(p)) > c.n {
		p = p[:c.n]
	}
	n, err := c.br.Read(p)
	c.n -= int64(n)
	if c.n == 0 && err == nil {
		c.br.ReadString('\n')
	}
	return n, err
}

func splitURL(u string) (scheme, host, path string, err error) {
	i := strings.Index(u, "://")
	if i < 0 {
		return "", "", "", fmt.Errorf("bad URL %q", u)
	}
	scheme = strings.ToLower(u[:i])
	rest := u[i+3:]
	j := strings.IndexByte(rest, '/')
	if j < 0 {
		host, path = rest, "/"
	} else {
		host, path = rest[:j], rest[j:]
	}
	return
}

func httpGet(url string) (*httpResp, error) {
	var lastErr error
	for attempt := 0; attempt < 3; attempt++ {
		u := url
		for redirects := 0; redirects < 6; redirects++ {
			resp, loc, err := httpOnce(u)
			if err != nil {
				lastErr = err
				break
			}
			if loc != "" {
				if strings.HasPrefix(loc, "/") {
					sch, h, _, _ := splitURL(u)
					loc = sch + "://" + h + loc
				}
				u = loc
				continue
			}
			if resp.Code == 200 {
				return resp, nil
			}
			resp.Body.Close()
			lastErr = fmt.Errorf("%s: HTTP %d", u, resp.Code)
			if resp.Code == 404 || resp.Code == 403 {
				return nil, lastErr
			}
			break
		}
		time.Sleep(time.Duration(attempt+1) * 400 * time.Millisecond)
	}
	return nil, lastErr
}

func httpOnce(u string) (*httpResp, string, error) {
	scheme, host, path, err := splitURL(u)
	if err != nil {
		return nil, "", err
	}
	if scheme == "https" {
		return externalGet(u)
	}
	if scheme != "http" {
		return nil, "", fmt.Errorf("unsupported URL scheme %s", scheme)
	}
	addr := host
	if !strings.Contains(addr, ":") || strings.HasSuffix(addr, "]") {
		addr += ":80"
	}
	reqTarget := path
	if px := firstEnv("http_proxy", "HTTP_PROXY"); px != "" && !noProxy(host) {
		_, ph, _, perr := splitURL(px)
		if perr == nil {
			addr = ph
			if !strings.Contains(addr, ":") {
				addr += ":80"
			}
			reqTarget = u
		}
	}
	for try := 0; try < 2; try++ {
		hc, err := getConn(addr)
		if err != nil {
			return nil, "", err
		}
		hc.c.SetWriteDeadline(time.Now().Add(30 * time.Second))
		_, err = fmt.Fprintf(hc.c, "GET %s HTTP/1.1\r\nHost: %s\r\nUser-Agent: kpkg/%s (KwickOS)\r\nAccept-Encoding: identity\r\nConnection: keep-alive\r\n\r\n",
			reqTarget, host, kpkgVersion)
		if err != nil {
			hc.c.Close()
			continue // stale pooled connection
		}
		hc.c.SetReadDeadline(time.Now().Add(60 * time.Second))
		status, err := hc.br.ReadString('\n')
		if err != nil {
			hc.c.Close()
			if try == 0 {
				continue
			}
			return nil, "", err
		}
		f := strings.Fields(status)
		if len(f) < 2 {
			hc.c.Close()
			return nil, "", fmt.Errorf("bad HTTP status line %q", status)
		}
		code, _ := strconv.Atoi(f[1])
		hdr := map[string]string{}
		for {
			l, err := hc.br.ReadString('\n')
			if err != nil {
				hc.c.Close()
				return nil, "", err
			}
			l = strings.TrimRight(l, "\r\n")
			if l == "" {
				break
			}
			if k, v, ok := strings.Cut(l, ":"); ok {
				hdr[strings.ToLower(strings.TrimSpace(k))] = strings.TrimSpace(v)
			}
		}
		dr := &deadlineReader{c: hc.c, r: hc.br}
		b := &body{hc: hc, addr: addr, reuse: !strings.EqualFold(hdr["connection"], "close") && strings.HasPrefix(f[0], "HTTP/1.1")}
		switch {
		case strings.Contains(strings.ToLower(hdr["transfer-encoding"]), "chunked"):
			b.r = &chunked{br: bufio.NewReader(dr)}
			b.reuse = false // inner bufio may hold bytes of the next response
		case hdr["content-length"] != "":
			n, _ := strconv.ParseInt(hdr["content-length"], 10, 64)
			b.r = io.LimitReader(dr, n)
			if n == 0 {
				b.done = true
			}
		default:
			b.r = dr
			b.reuse = false
		}
		if code >= 300 && code < 400 && hdr["location"] != "" {
			io.Copy(io.Discard, b)
			b.Close()
			return nil, hdr["location"], nil
		}
		return &httpResp{Body: b, Code: code}, "", nil
	}
	return nil, "", errors.New("connection failed")
}

func firstEnv(ks ...string) string {
	for _, k := range ks {
		if v := os.Getenv(k); v != "" {
			return v
		}
	}
	return ""
}

func noProxy(host string) bool {
	np := firstEnv("no_proxy", "NO_PROXY")
	h := strings.Split(host, ":")[0]
	for _, x := range strings.Split(np, ",") {
		x = strings.TrimSpace(x)
		if x != "" && (x == "*" || h == x || strings.HasSuffix(h, "."+strings.TrimPrefix(x, "."))) {
			return true
		}
	}
	return false
}

type cmdBody struct {
	io.ReadCloser
	cmd *exec.Cmd
}

func (c *cmdBody) Close() error {
	c.ReadCloser.Close()
	return c.cmd.Wait()
}

// externalGet fetches https:// URLs via curl or (busybox) wget.
func externalGet(u string) (*httpResp, string, error) {
	var cmd *exec.Cmd
	if p, err := exec.LookPath("curl"); err == nil {
		cmd = exec.Command(p, "-fsSL", "--retry", "2", u)
	} else if p, err := exec.LookPath("wget"); err == nil {
		cmd = exec.Command(p, "-q", "-O", "-", u)
	} else {
		return nil, "", errors.New("https:// sources need curl or wget (apt install curl, or use http:// mirrors — packages are signature-verified either way)")
	}
	// Download to a temp file first so HTTP errors (404 pages etc.) surface
	// as errors instead of being parsed as content.
	tmp, err := os.CreateTemp("", "kpkg-dl-")
	if err != nil {
		return nil, "", err
	}
	os.Remove(tmp.Name()) // unlinked; kept alive by the open fd
	cmd.Stdout = tmp
	cmd.Stderr = nil
	if err := cmd.Run(); err != nil {
		tmp.Close()
		return &httpResp{Body: io.NopCloser(strings.NewReader("")), Code: 404}, "", nil
	}
	tmp.Seek(0, io.SeekStart)
	return &httpResp{Body: tmp, Code: 200}, "", nil
}
