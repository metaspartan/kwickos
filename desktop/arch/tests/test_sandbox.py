import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

WORK = tempfile.mkdtemp(prefix="kwick-arch-test-")
os.chmod(WORK, 0o755)
os.environ["KWICK_ARCH_DIR"] = os.path.join(WORK, "base")
os.environ["KWICK_ARCH_CONF"] = os.path.join(WORK, "arch.conf")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "rootfs", "usr", "lib", "kwick", "arch"))

from kwickarch import container, ops, safefs, util


def slurp(path, mode="rb"):
    with open(path, mode) as f:
        return f.read()


def put(path, data=b""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


class Fresh(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(dir=WORK)
        os.chmod(self.d, 0o755)
        self.root = os.path.join(self.d, "root")
        os.makedirs(self.root)
        self.victim = os.path.join(self.d, "victim")
        put(self.victim, b"secret\n")
        os.chmod(self.victim, 0o600)

    def victim_intact(self):
        self.assertEqual(slurp(self.victim), b"secret\n")
        self.assertEqual(stat.S_IMODE(os.stat(self.victim).st_mode), 0o600)


class SafeFs(Fresh):
    def test_read_refuses_final_symlink(self):
        os.makedirs(os.path.join(self.root, "etc"))
        os.symlink(self.victim, os.path.join(self.root, "etc/passwd"))
        with self.assertRaises(OSError):
            safefs.read_bytes(self.root, "etc/passwd")

    def test_read_refuses_symlinked_directory(self):
        os.symlink(self.d, os.path.join(self.root, "etc"))
        with self.assertRaises(OSError):
            safefs.read_bytes(self.root, "etc/victim")

    def test_read_refuses_fifo(self):
        os.mkfifo(os.path.join(self.root, "pipe"))
        with self.assertRaises(OSError):
            safefs.read_bytes(self.root, "pipe")

    def test_write_replaces_symlink_not_target(self):
        os.makedirs(os.path.join(self.root, "etc/pacman.d"))
        os.symlink(self.victim, os.path.join(self.root, "etc/pacman.d/mirrorlist"))
        safefs.write_text(self.root, "etc/pacman.d/mirrorlist", "Server = x\n", 0o644)
        self.victim_intact()
        p = os.path.join(self.root, "etc/pacman.d/mirrorlist")
        self.assertFalse(os.path.islink(p))
        self.assertEqual(slurp(p, "r"), "Server = x\n")
        self.assertEqual(os.listdir(os.path.dirname(p)), ["mirrorlist"])

    def test_write_refuses_symlinked_directory(self):
        os.makedirs(os.path.join(self.d, "outside"))
        os.symlink(os.path.join(self.d, "outside"), os.path.join(self.root, "etc"))
        with self.assertRaises(OSError):
            safefs.write_text(self.root, "etc/x", "y")
        self.assertEqual(os.listdir(os.path.join(self.d, "outside")), [])

    def test_makedirs_refuses_symlink(self):
        os.makedirs(os.path.join(self.d, "outside"))
        os.symlink(os.path.join(self.d, "outside"), os.path.join(self.root, "usr"))
        with self.assertRaises(OSError):
            safefs.makedirs(self.root, "usr/local/bin")
        self.assertEqual(os.listdir(os.path.join(self.d, "outside")), [])

    def test_dotdot_rejected(self):
        with self.assertRaises(OSError):
            safefs.read_bytes(self.root, "../victim")

    def test_copy_in_refuses_symlink_source(self):
        bdir = os.path.join(self.d, "bdir")
        os.makedirs(os.path.join(bdir, "out"))
        os.symlink(self.victim, os.path.join(bdir, "out/x-1-1-any.pkg.tar.zst"))
        with self.assertRaises(OSError):
            safefs.copy_in(bdir, "out/x-1-1-any.pkg.tar.zst", self.root, "var/cache/kwick-aur/x-1-1-any.pkg.tar.zst")
        self.assertEqual(safefs.listdir(self.root, "var/cache/kwick-aur"), [])

    def test_copy_in_refuses_symlinked_out_directory(self):
        bdir = os.path.join(self.d, "bdir")
        os.makedirs(bdir)
        os.makedirs(os.path.join(self.d, "elsewhere"))
        put(os.path.join(self.d, "elsewhere/x.pkg.tar.zst"), b"data")
        os.symlink(os.path.join(self.d, "elsewhere"), os.path.join(bdir, "out"))
        self.assertEqual(safefs.listdir(bdir, "out"), [])
        with self.assertRaises(OSError):
            safefs.copy_in(bdir, "out/x.pkg.tar.zst", self.root, "p/x.pkg.tar.zst")

    def test_copy_in_regular(self):
        bdir = os.path.join(self.d, "bdir")
        put(os.path.join(bdir, "out/x.pkg.tar.zst"), b"data")
        safefs.copy_in(bdir, "out/x.pkg.tar.zst", self.root, "var/cache/kwick-aur/x.pkg.tar.zst")
        self.assertEqual(slurp(os.path.join(self.root, "var/cache/kwick-aur/x.pkg.tar.zst")), b"data")

    def test_clear_dir_does_not_follow(self):
        os.makedirs(os.path.join(self.d, "outside"))
        put(os.path.join(self.d, "outside/keep"), b"1")
        os.makedirs(os.path.join(self.root, "var/cache"))
        os.symlink(os.path.join(self.d, "outside"), os.path.join(self.root, "var/cache/pacman"))
        safefs.clear_dir(self.root, "var/cache/pacman/pkg")
        self.assertTrue(os.path.exists(os.path.join(self.d, "outside/keep")))

    def test_clear_dir_removes_files(self):
        put(os.path.join(self.root, "var/cache/pacman/pkg/a"), b"1")
        os.symlink(self.victim, os.path.join(self.root, "var/cache/pacman/pkg/b"))
        safefs.clear_dir(self.root, "var/cache/pacman/pkg")
        self.assertEqual(os.listdir(os.path.join(self.root, "var/cache/pacman/pkg")), [])
        self.victim_intact()

    def test_copy_out_refuses_symlink(self):
        os.makedirs(os.path.join(self.root, "sync"))
        os.symlink(self.victim, os.path.join(self.root, "sync/core.db"))
        dest = os.path.join(self.d, "core.db")
        with self.assertRaises(OSError):
            safefs.copy_out(self.root, "sync/core.db", dest)
        self.assertFalse(os.path.exists(dest))


@unittest.skipUnless(os.geteuid() == 0, "needs root")
class Adopt(Fresh):
    def test_adopt_does_not_follow_symlinks(self):
        os.chown(self.victim, 0, 0)
        put(os.path.join(self.root, "usr/bin/real"), b"x")
        os.symlink(self.victim, os.path.join(self.root, "usr/bin/link"))
        os.symlink(self.d, os.path.join(self.root, "usr/dirlink"))
        os.chmod(os.path.join(self.root, "usr/bin/real"), 0o4755)
        container.adopt(self.root)
        st = os.stat(os.path.join(self.root, "usr/bin/real"))
        self.assertEqual(st.st_uid, util.ID_BASE)
        self.assertEqual(stat.S_IMODE(st.st_mode), 0o4755)
        self.assertEqual(os.stat(self.victim).st_uid, 0)
        self.assertEqual(os.stat(self.d).st_uid, 0)
        self.assertEqual(os.lstat(os.path.join(self.root, "usr/bin/link")).st_uid, util.ID_BASE)


@unittest.skipUnless(os.geteuid() == 0, "needs root")
class ConfigureRoot(Fresh):
    def setUp(self):
        super().setUp()
        self.old = util.ROOT
        util.ROOT = self.root
        put(os.path.join(self.root, "etc/pacman.conf"), b"[options]\n#ParallelDownloads = 5\n")
        put(os.path.join(self.root, "usr/bin/pacman"), b"")
        os.makedirs(os.path.join(self.root, "etc/pacman.d"))

    def tearDown(self):
        util.ROOT = self.old

    def test_mirrorlist_symlink_does_not_hit_host_file(self):
        os.symlink(self.victim, os.path.join(self.root, "etc/pacman.d/mirrorlist"))
        container.configure_root()
        self.victim_intact()
        self.assertIn("Server = ", slurp(os.path.join(self.root, "etc/pacman.d/mirrorlist"), "r"))

    def test_every_written_path_symlink(self):
        for rel in ("etc/locale.gen", "etc/locale.conf", "usr/local/bin/xdg-open", "etc/localtime", "etc/hostname"):
            p = os.path.join(self.root, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            os.symlink(self.victim, p)
        container.configure_root()
        self.victim_intact()
        self.assertTrue(os.access(os.path.join(self.root, "usr/local/bin/xdg-open"), os.X_OK))
        self.assertFalse(os.path.islink(os.path.join(self.root, "etc/localtime")))

    def test_symlinked_parent_does_not_create_host_dirs(self):
        outside = os.path.join(self.d, "outside")
        os.makedirs(outside)
        os.makedirs(os.path.join(self.root, "usr/local"))
        os.symlink(outside, os.path.join(self.root, "usr/local/share"))
        with self.assertRaises(OSError):
            container.configure_root()
        self.assertEqual(os.listdir(outside), [])

    def test_pacman_conf_symlink_refused(self):
        os.unlink(os.path.join(self.root, "etc/pacman.conf"))
        os.symlink(self.victim, os.path.join(self.root, "etc/pacman.conf"))
        with self.assertRaises(OSError):
            container.pacman_conf_ok()


@unittest.skipUnless(os.geteuid() == 0, "needs root")
class BuildOne(Fresh):
    def setUp(self):
        super().setUp()
        self.old = (util.ROOT, util.BUILD)
        util.ROOT = self.root
        util.BUILD = os.path.join(self.d, "build")
        put(os.path.join(self.root, "usr/bin/pacman"), b"")
        self.seen = []

    def tearDown(self):
        util.ROOT, util.BUILD = self.old

    def run_build(self, plant):
        def fake_in_root(cmd, **kw):
            if cmd[0] == "makepkg" and "--noextract" in cmd:
                plant(kw["binds"][0][0])
            return subprocess.CompletedProcess(cmd, 0)

        def fake_transaction(args):
            for a in args:
                if a.startswith("/"):
                    p = os.path.join(self.root, a.lstrip("/"))
                    self.seen.append(os.path.isfile(p) and not os.path.islink(p))

        r = {"pkgbase": "x", "commit": "0123456789abcdef", "files": {}, "srcinfo": {"base": {}}}
        orig = (container.in_root, container.transaction)
        container.in_root, container.transaction = fake_in_root, fake_transaction
        try:
            ops.build_one(r, ["x"], False, False)
        finally:
            container.in_root, container.transaction = orig

    def test_symlink_output_not_copied(self):
        def plant(bdir):
            os.symlink(self.victim, os.path.join(bdir, "out/x-1-1-any.pkg.tar.zst"))

        with self.assertRaises(util.Fail):
            self.run_build(plant)
        self.victim_intact()
        self.assertEqual(safefs.listdir(self.root, "var/cache/kwick-aur"), [])

    def test_regular_output_staged_and_removed(self):
        def plant(bdir):
            put(os.path.join(bdir, "out/x-1-1-any.pkg.tar.zst"), b"pkg")

        self.run_build(plant)
        self.assertEqual(self.seen, [True])
        self.assertEqual(safefs.listdir(self.root, "var/cache/kwick-aur"), [])


@unittest.skipUnless(os.geteuid() == 0 and shutil.which("bwrap"), "needs root and bwrap")
class Sandbox(Fresh):
    def setUp(self):
        super().setUp()
        self.old = util.ROOT
        util.ROOT = self.root
        for link, target in (("bin", "usr/bin"), ("lib", "usr/lib"), ("lib64", "usr/lib64"), ("sbin", "usr/sbin")):
            os.symlink(target, os.path.join(self.root, link))
        self.binds = [("/usr", "/usr", False)]

    def tearDown(self):
        util.ROOT = self.old

    def sh(self, script, **kw):
        return container.in_root(["sh", "-c", script], check=False, capture=True, net=False, binds=self.binds, **kw)

    def blocked(self, script, **kw):
        r = self.sh(script + "; echo rc=$?", **kw)
        self.assertNotIn("bwrap:", r.stderr)
        self.assertIn("unshare", r.stderr)
        self.assertIn("rc=1", r.stdout)

    def test_control_unshare_works_outside_the_sandbox(self):
        self.assertEqual(subprocess.run(["unshare", "-U", "-r", "true"]).returncode, 0)

    def test_nested_userns_blocked_for_root(self):
        self.blocked("unshare -U -r true")

    def test_nested_userns_blocked_for_builder(self):
        self.blocked("unshare -U -r true", user=True)

    def test_nested_userns_blocked_with_other_flags(self):
        self.blocked("unshare --user --map-root-user --mount true")

    def test_sysctl_cannot_be_raised(self):
        self.blocked("echo 100 > /proc/sys/user/max_user_namespaces; unshare -U -r true")

    def test_id_mapping_intact(self):
        r = self.sh("touch /x && chown 1000:1000 /x && chown 64990:64990 /x && stat -c %u:%g /x")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.split()[0], "64990:64990")
        self.assertEqual(os.stat(os.path.join(self.root, "x")).st_uid, util.ID_BASE + 64990)

    def test_builder_can_run(self):
        r = self.sh("id -u", user=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.strip(), str(util.BUILDER_UID))


if __name__ == "__main__":
    unittest.main(verbosity=2)
