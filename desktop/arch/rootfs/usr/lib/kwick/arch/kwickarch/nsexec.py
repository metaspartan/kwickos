import os
import sys


def die(msg, status=125):
    sys.stderr.write("kwick-arch: %s\n" % msg)
    sys.stderr.flush()
    os._exit(status)


def main():
    if len(sys.argv) < 5 or sys.argv[3] != "--":
        die("usage: nsexec.py BASE COUNT -- COMMAND...", 2)
    base = int(sys.argv[1])
    count = int(sys.argv[2])
    argv = sys.argv[4:]
    me = os.getpid()
    r, w = os.pipe()
    pid = os.fork()
    if pid == 0:
        os.close(w)
        if os.read(r, 1) != b"u":
            os._exit(1)
        try:
            for name in ("uid_map", "gid_map"):
                with open("/proc/%d/%s" % (me, name), "w") as f:
                    f.write("0 %d %d\n" % (base, count))
        except OSError as e:
            die("could not map the environment's ids: %s" % e)
        os._exit(0)
    os.close(r)
    try:
        os.unshare(os.CLONE_NEWUSER)
    except OSError as e:
        os.close(w)
        os.waitpid(pid, 0)
        die("could not create a user namespace: %s" % e)
    os.write(w, b"u")
    os.close(w)
    _, status = os.waitpid(pid, 0)
    if os.waitstatus_to_exitcode(status) != 0:
        die("the user namespace was not set up")
    os.setgroups([])
    os.setresgid(0, 0, 0)
    os.setresuid(0, 0, 0)
    os.chdir("/")
    try:
        os.execvp(argv[0], argv)
    except OSError as e:
        die("could not run %s: %s" % (argv[0], e))


if __name__ == "__main__":
    main()
