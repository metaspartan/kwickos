package main

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
	"time"
	"unsafe"
)

func ioctl(fd, req, arg uintptr) error {
	_, _, e := syscall.Syscall(syscall.SYS_IOCTL, fd, req, arg)
	if e != 0 {
		return e
	}
	return nil
}

func isTerminal(fd int) bool {
	var t syscall.Termios
	return ioctl(uintptr(fd), syscall.TCGETS, uintptr(unsafe.Pointer(&t))) == nil
}

func getTermios(fd int) (*syscall.Termios, error) {
	var t syscall.Termios
	if err := ioctl(uintptr(fd), syscall.TCGETS, uintptr(unsafe.Pointer(&t))); err != nil {
		return nil, err
	}
	return &t, nil
}

func setTermios(fd int, t *syscall.Termios) error {
	return ioctl(uintptr(fd), syscall.TCSETS, uintptr(unsafe.Pointer(t)))
}

func makeRaw(fd int) (*syscall.Termios, error) {
	old, err := getTermios(fd)
	if err != nil {
		return nil, err
	}
	t := *old
	t.Iflag &^= syscall.IGNBRK | syscall.BRKINT | syscall.PARMRK | syscall.ISTRIP | syscall.INLCR | syscall.IGNCR | syscall.ICRNL | syscall.IXON
	t.Oflag &^= syscall.OPOST
	t.Lflag &^= syscall.ECHO | syscall.ECHONL | syscall.ICANON | syscall.ISIG | syscall.IEXTEN
	t.Cflag &^= syscall.CSIZE | syscall.PARENB
	t.Cflag |= syscall.CS8
	t.Cc[syscall.VMIN] = 1
	t.Cc[syscall.VTIME] = 0
	if err := setTermios(fd, &t); err != nil {
		return nil, err
	}
	return old, nil
}

func readNoEcho(prompt string) (string, error) {
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		return "", err
	}
	defer tty.Close()
	fmt.Fprint(tty, prompt)
	old, err := getTermios(int(tty.Fd()))
	if err != nil {
		return "", err
	}
	t := *old
	t.Lflag &^= syscall.ECHO
	setTermios(int(tty.Fd()), &t)
	defer setTermios(int(tty.Fd()), old)
	var b []byte
	buf := make([]byte, 1)
	for {
		n, err := tty.Read(buf)
		if n == 0 || err != nil || buf[0] == '\n' || buf[0] == '\r' {
			break
		}
		b = append(b, buf[0])
	}
	fmt.Fprintln(tty)
	return string(b), nil
}

type winsize struct{ Row, Col, X, Y uint16 }

func openPty() (*os.File, *os.File, error) {
	m, err := os.OpenFile("/dev/ptmx", os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		return nil, nil, err
	}
	var unlock int32
	if err := ioctl(m.Fd(), syscall.TIOCSPTLCK, uintptr(unsafe.Pointer(&unlock))); err != nil {
		m.Close()
		return nil, nil, err
	}
	var n uint32
	if err := ioctl(m.Fd(), syscall.TIOCGPTN, uintptr(unsafe.Pointer(&n))); err != nil {
		m.Close()
		return nil, nil, err
	}
	s, err := os.OpenFile(fmt.Sprintf("/dev/pts/%d", n), os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		m.Close()
		return nil, nil, err
	}
	return m, s, nil
}

func copyWinsize(from, to uintptr) {
	var ws winsize
	if ioctl(from, syscall.TIOCGWINSZ, uintptr(unsafe.Pointer(&ws))) == nil {
		ioctl(to, syscall.TIOCSWINSZ, uintptr(unsafe.Pointer(&ws)))
	}
}

func exitCode(err error) int {
	if err == nil {
		return 0
	}
	if ee, ok := err.(*exec.ExitError); ok {
		if ws, ok := ee.Sys().(syscall.WaitStatus); ok && ws.Signaled() {
			return 128 + int(ws.Signal())
		}
		return ee.ExitCode()
	}
	return 1
}

func runWithPty(c *exec.Cmd) int {
	m, s, err := openPty()
	if err != nil {
		warnf("no pseudo terminal (%v); running without one", err)
		return runPlain(c)
	}
	copyWinsize(0, m.Fd())
	if t, err := getTermios(0); err == nil {
		setTermios(int(s.Fd()), t)
	}
	c.Stdin, c.Stdout, c.Stderr = s, s, s
	c.SysProcAttr = &syscall.SysProcAttr{Setsid: true, Setctty: true, Ctty: 0}
	if err := c.Start(); err != nil {
		m.Close()
		s.Close()
		warnf("%v", err)
		return 127
	}
	s.Close()
	old, rawErr := makeRaw(0)
	restore := func() {
		if rawErr == nil {
			setTermios(0, old)
		}
	}
	sig := make(chan os.Signal, 8)
	signal.Notify(sig, syscall.SIGWINCH, syscall.SIGTERM, syscall.SIGHUP, syscall.SIGINT, syscall.SIGQUIT)
	go func() {
		for sg := range sig {
			if sg == syscall.SIGWINCH {
				copyWinsize(0, m.Fd())
				continue
			}
			if sg == syscall.SIGTERM || sg == syscall.SIGHUP {
				if c.Process != nil {
					c.Process.Signal(sg)
				}
			}
		}
	}()
	go io.Copy(m, os.Stdin)
	done := make(chan struct{})
	go func() {
		io.Copy(os.Stdout, m)
		close(done)
	}()
	werr := c.Wait()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
	}
	restore()
	signal.Stop(sig)
	m.Close()
	return exitCode(werr)
}

func runPlain(c *exec.Cmd) int {
	c.Stdin, c.Stdout, c.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := c.Start(); err != nil {
		warnf("%v", err)
		return 127
	}
	sig := make(chan os.Signal, 8)
	signal.Notify(sig, syscall.SIGTERM, syscall.SIGHUP, syscall.SIGINT, syscall.SIGQUIT)
	go func() {
		for sg := range sig {
			if c.Process != nil && (sg == syscall.SIGTERM || sg == syscall.SIGHUP) {
				c.Process.Signal(sg)
			}
		}
	}()
	err := c.Wait()
	signal.Stop(sig)
	return exitCode(err)
}
