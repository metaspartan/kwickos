import errno
import os
import stat

DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
FILE_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_NOCTTY | os.O_CLOEXEC
MAX_READ = 1 << 30


def split(rel):
    out = []
    for p in rel.split("/"):
        if p in ("", "."):
            continue
        if p == "..":
            raise OSError(errno.EINVAL, "path escapes the root", rel)
        out.append(p)
    return out


def open_dir(root, rel="", create=False, mode=0o755):
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for name in split(rel):
            if create:
                try:
                    os.mkdir(name, mode, dir_fd=fd)
                except FileExistsError:
                    pass
            nfd = os.open(name, DIR_FLAGS, dir_fd=fd)
            os.close(fd)
            fd = nfd
        return fd
    except BaseException:
        os.close(fd)
        raise


def makedirs(root, rel, mode=0o755):
    os.close(open_dir(root, rel, create=True, mode=mode))


def parent(root, rel, create=False):
    parts = split(rel)
    if not parts:
        raise OSError(errno.EINVAL, "empty path", rel)
    return open_dir(root, "/".join(parts[:-1]), create=create), parts[-1]


def open_file(root, rel):
    dfd, name = parent(root, rel)
    try:
        fd = os.open(name, FILE_FLAGS, dir_fd=dfd)
    finally:
        os.close(dfd)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise OSError(errno.EINVAL, "not a regular file", rel)
    except BaseException:
        os.close(fd)
        raise
    return fd


def read_bytes(root, rel, limit=MAX_READ):
    fd = open_file(root, rel)
    try:
        chunks = []
        total = 0
        while True:
            c = os.read(fd, 1 << 20)
            if not c:
                break
            total += len(c)
            if total > limit:
                raise OSError(errno.EFBIG, "file is too large", rel)
            chunks.append(c)
        return b"".join(chunks), os.fstat(fd)
    finally:
        os.close(fd)


def read_text(root, rel, errors="strict"):
    return read_bytes(root, rel)[0].decode("utf-8", errors)


def lstat(root, rel):
    try:
        dfd, name = parent(root, rel)
    except (FileNotFoundError, NotADirectoryError):
        return None
    try:
        return os.stat(name, dir_fd=dfd, follow_symlinks=False)
    except FileNotFoundError:
        return None
    finally:
        os.close(dfd)


def listdir(root, rel):
    try:
        fd = open_dir(root, rel)
    except (FileNotFoundError, NotADirectoryError):
        return []
    try:
        return os.listdir(fd)
    finally:
        os.close(fd)


def unlink(root, rel):
    try:
        dfd, name = parent(root, rel)
    except (FileNotFoundError, NotADirectoryError):
        return
    try:
        os.unlink(name, dir_fd=dfd)
    except FileNotFoundError:
        pass
    finally:
        os.close(dfd)


def clear_dir(root, rel):
    try:
        fd = open_dir(root, rel)
    except (FileNotFoundError, NotADirectoryError):
        return
    try:
        for name in os.listdir(fd):
            try:
                if not stat.S_ISDIR(os.stat(name, dir_fd=fd, follow_symlinks=False).st_mode):
                    os.unlink(name, dir_fd=fd)
            except OSError:
                pass
    finally:
        os.close(fd)


def stage(dfd, name, writer, mode):
    tmp = name + ".kwick-new"
    try:
        os.unlink(tmp, dir_fd=dfd)
    except FileNotFoundError:
        pass
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600, dir_fd=dfd)
    try:
        try:
            writer(fd)
            os.fchmod(fd, mode)
        finally:
            os.close(fd)
        os.rename(tmp, name, src_dir_fd=dfd, dst_dir_fd=dfd)
    except BaseException:
        try:
            os.unlink(tmp, dir_fd=dfd)
        except OSError:
            pass
        raise


def write_bytes(root, rel, data, mode=0o644):
    dfd, name = parent(root, rel, create=True)

    def writer(fd):
        view = memoryview(data)
        while view:
            view = view[os.write(fd, view):]

    try:
        stage(dfd, name, writer, mode)
    finally:
        os.close(dfd)


def write_text(root, rel, text, mode=0o644):
    write_bytes(root, rel, text.encode("utf-8"), mode)


def copy_in(src_root, src_rel, dst_root, dst_rel, mode=0o644):
    sfd = open_file(src_root, src_rel)
    try:
        dfd, name = parent(dst_root, dst_rel, create=True)
        try:
            def writer(fd):
                while True:
                    c = os.read(sfd, 1 << 20)
                    if not c:
                        break
                    view = memoryview(c)
                    while view:
                        view = view[os.write(fd, view):]

            stage(dfd, name, writer, mode)
        finally:
            os.close(dfd)
    finally:
        os.close(sfd)


def copy_out(src_root, src_rel, dest, mode=0o644):
    sfd = open_file(src_root, src_rel)
    try:
        st = os.fstat(sfd)
        fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
        try:
            while True:
                c = os.read(sfd, 1 << 20)
                if not c:
                    break
                view = memoryview(c)
                while view:
                    view = view[os.write(fd, view):]
            os.fchmod(fd, mode)
            os.utime(fd, ns=(st.st_atime_ns, st.st_mtime_ns))
        finally:
            os.close(fd)
    finally:
        os.close(sfd)
