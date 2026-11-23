import ctypes
import os
import sys


def die(msg, status=125):
    sys.stderr.write("kwick-arch: %s\n" % msg)
    sys.stderr.flush()
    os._exit(status)


def enter(me, outside, count, what):
    r, w = os.pipe()
    pid = os.fork()
    if pid == 0:
        os.close(w)
        if os.read(r, 1) != b"u":
            os._exit(1)
        try:
            for name in ("uid_map", "gid_map"):
                with open("/proc/%d/%s" % (me, name), "w") as f:
                    f.write("0 %d %d\n" % (outside, count))
        except OSError as e:
            die("could not map the environment's ids: %s" % e)
        os._exit(0)
    os.close(r)
    try:
        os.unshare(os.CLONE_NEWUSER)
    except OSError as e:
        os.close(w)
        os.waitpid(pid, 0)
        die("could not create %s: %s" % (what, e))
    if ctypes.CDLL(None, use_errno=True).prctl(4, 1, 0, 0, 0) != 0:
        os.close(w)
        os.waitpid(pid, 0)
        die("could not make the process dumpable")
    os.write(w, b"u")
    os.close(w)
    _, status = os.waitpid(pid, 0)
    if os.waitstatus_to_exitcode(status) != 0:
        die("the user namespace was not set up")
    os.setgroups([])
    os.setresgid(0, 0, 0)
    os.setresuid(0, 0, 0)


def main():
    if len(sys.argv) < 5 or sys.argv[3] != "--":
        die("usage: nsexec.py BASE COUNT -- COMMAND...", 2)
    base = int(sys.argv[1])
    count = int(sys.argv[2])
    argv = sys.argv[4:]
    me = os.getpid()
    enter(me, base, count, "a user namespace")
    try:
        with open("/proc/sys/user/max_user_namespaces", "w") as f:
            f.write("1\n")
    except OSError as e:
        die("could not forbid nested user namespaces: %s" % e)
    enter(me, 0, count, "the inner user namespace")
    os.chdir("/")
    try:
        os.execvp(argv[0], argv)
    except OSError as e:
        die("could not run %s: %s" % (argv[0], e))


if __name__ == "__main__":
    main()
