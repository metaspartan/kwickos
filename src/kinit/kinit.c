/* SPDX-License-Identifier: MIT */
#define _GNU_SOURCE
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <limits.h>
#include <linux/loop.h>
#include <linux/netlink.h>
#include <linux/watchdog.h>
#include <net/if.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/resource.h>
#include <sys/signalfd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/sysmacros.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#define KINIT_VERSION "0.1.0"
#define SOCK_PATH "/run/kinit.sock"
#define LOG_DIR "/var/log/kinit"
#define MAX_SVC 512
#define MAX_EXEC 8
#define MAX_ENV 48

static const char *unit_dirs[] = {
	"/etc/systemd/system", "/run/systemd/transient", "/usr/lib/systemd/system",
	"/lib/systemd/system", NULL };

static int is_pid1;
static int cmd_tmpfiles(int argc, char **argv);
static int verbose;

static long now_ms(clockid_t c)
{
	struct timespec ts;
	clock_gettime(c, &ts);
	return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

static void say(const char *fmt, ...)
{
	char buf[512] = "kinit: ";
	va_list ap;
	va_start(ap, fmt);
	int n = vsnprintf(buf + 7, sizeof buf - 9, fmt, ap);
	va_end(ap);
	if (n < 0) return;
	if (n > (int)sizeof buf - 9) n = sizeof buf - 9;
	n += 7;
	buf[n++] = '\n';
	if (is_pid1) {
		int fd = open("/dev/console", O_WRONLY | O_NOCTTY | O_CLOEXEC);
		if (fd >= 0) { (void)!write(fd, buf, n); close(fd); return; }
	}
	(void)!write(2, buf, n);
}

static int read_file(const char *path, char *buf, size_t sz)
{
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0) return -1;
	ssize_t n = read(fd, buf, sz - 1);
	close(fd);
	if (n < 0) return -1;
	buf[n] = 0;
	return (int)n;
}

static int write_file(const char *path, const char *s)
{
	int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
	if (fd < 0) return -1;
	ssize_t n = write(fd, s, strlen(s));
	close(fd);
	return n < 0 ? -1 : 0;
}

static char *trim(char *s)
{
	while (isspace((unsigned char)*s)) s++;
	char *e = s + strlen(s);
	while (e > s && isspace((unsigned char)e[-1])) *--e = 0;
	return s;
}

static void mkdir_p(const char *path, mode_t mode)
{
	char tmp[PATH_MAX];
	snprintf(tmp, sizeof tmp, "%s", path);
	for (char *p = tmp + 1; *p; p++) {
		if (*p == '/') { *p = 0; mkdir(tmp, mode); *p = '/'; }
	}
	mkdir(tmp, mode);
}

static void child_signals(void)
{
	sigset_t none;
	sigemptyset(&none);
	sigprocmask(SIG_SETMASK, &none, NULL);
	signal(SIGPIPE, SIG_DFL);
}

static int run_wait(char *const argv[])
{
	pid_t p = fork();
	if (p < 0) return -1;
	if (p == 0) {
		child_signals();
		execvp(argv[0], argv);
		_exit(127);
	}
	int st;
	while (waitpid(p, &st, 0) < 0 && errno == EINTR) ;
	return WIFEXITED(st) ? WEXITSTATUS(st) : 128 + WTERMSIG(st);
}

static void spawn_bg(char *const argv[])
{
	pid_t p = fork();
	if (p == 0) {
		child_signals();
		setsid();
		execvp(argv[0], argv);
		_exit(127);
	}
}

static const char *cmdline_get(const char *key)
{
	static char cl[4096];
	static int loaded;
	static char val[512];
	if (!loaded) { if (read_file("/proc/cmdline", cl, sizeof cl) < 0) cl[0] = 0; loaded = 1; }
	size_t kl = strlen(key);
	const char *found = NULL;
	for (char *p = cl; *p;) {
		while (*p == ' ' || *p == '\n') p++;
		if (!*p) break;
		char *e = p;
		while (*e && *e != ' ' && *e != '\n') e++;
		if ((size_t)(e - p) >= kl && !strncmp(p, key, kl) && (p[kl] == '=' || p + kl == e)) {
			size_t vl = p + kl == e ? 0 : (size_t)(e - p - kl - 1);
			if (vl >= sizeof val) vl = sizeof val - 1;
			memcpy(val, p[kl] == '=' ? p + kl + 1 : "", vl);
			val[vl] = 0;
			found = val;
		}
		p = e;
	}
	return found;
}

static const char *cmdline_dup(const char *key, char *buf, size_t sz)
{
	const char *v = cmdline_get(key);
	if (!v) return NULL;
	snprintf(buf, sz, "%s", v);
	return buf;
}

static int dev_matches(const char *dev, const char *kind, const char *want)
{
	unsigned char sb[2048];
	int fd = open(dev, O_RDONLY | O_CLOEXEC);
	if (fd < 0) return 0;
	int ok = 0;
	char got[64] = "";
	if (pread(fd, sb, 1024, 1024) == 1024 && sb[56] == 0x53 && sb[57] == 0xEF) {
		if (!strcmp(kind, "LABEL")) { memcpy(got, sb + 120, 16); got[16] = 0; }
		else {
			unsigned char *u = sb + 104;
			snprintf(got, sizeof got, "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
				u[0],u[1],u[2],u[3],u[4],u[5],u[6],u[7],u[8],u[9],u[10],u[11],u[12],u[13],u[14],u[15]);
		}
	} else if (pread(fd, sb, 2048, 32768) == 2048 && !memcmp(sb + 1, "CD001", 5)) {
		if (!strcmp(kind, "LABEL")) {
			memcpy(got, sb + 40, 32); got[32] = 0;
			for (int i = 31; i >= 0 && got[i] == ' '; i--) got[i] = 0;
		}
	} else if (pread(fd, sb, 512, 0) == 512 && sb[510] == 0x55 && sb[511] == 0xAA &&
		   !memcmp(sb + 82, "FAT32", 5)) {
		if (!strcmp(kind, "LABEL")) {
			memcpy(got, sb + 71, 11); got[11] = 0;
			for (int i = 10; i >= 0 && got[i] == ' '; i--) got[i] = 0;
		}
	}
	close(fd);
	if (got[0] && !strcasecmp(got, want)) ok = 1;
	return ok;
}

static int resolve_dev(const char *spec, char *out, size_t outsz)
{
	if (spec[0] == '/') { snprintf(out, outsz, "%s", spec); return access(out, F_OK) == 0; }
	const char *eq = strchr(spec, '=');
	if (!eq) return 0;
	char kind[16];
	snprintf(kind, sizeof kind, "%.*s", (int)(eq - spec), spec);
	const char *want = eq + 1;
	DIR *d = opendir("/sys/class/block");
	if (!d) return 0;
	struct dirent *de;
	int found = 0;
	while (!found && (de = readdir(d))) {
		if (de->d_name[0] == '.') continue;
		char p[PATH_MAX], buf[1024];
		snprintf(out, outsz, "/dev/%s", de->d_name);
		if (!strcmp(kind, "PARTLABEL")) {
			snprintf(p, sizeof p, "/sys/class/block/%s/uevent", de->d_name);
			if (read_file(p, buf, sizeof buf) > 0) {
				char *n = strstr(buf, "PARTNAME=");
				if (n) { n += 9; char *e = strchr(n, '\n'); if (e) *e = 0;
					if (!strcmp(n, want)) found = 1; }
			}
		} else if (!strcmp(kind, "LABEL") || !strcmp(kind, "UUID")) {
			found = dev_matches(out, kind, want);
		}
	}
	closedir(d);
	return found;
}

static int loop_attach(const char *file, char *dev, size_t devsz)
{
	int ctl = open("/dev/loop-control", O_RDWR | O_CLOEXEC);
	if (ctl < 0) return -1;
	int n = ioctl(ctl, LOOP_CTL_GET_FREE);
	close(ctl);
	if (n < 0) return -1;
	snprintf(dev, devsz, "/dev/loop%d", n);
	int lfd = open(dev, O_RDWR | O_CLOEXEC);
	int ffd = open(file, O_RDONLY | O_CLOEXEC);
	if (lfd < 0 || ffd < 0) return -1;
	struct loop_config cfg;
	memset(&cfg, 0, sizeof cfg);
	cfg.fd = ffd;
	cfg.info.lo_flags = LO_FLAGS_READ_ONLY;
	cfg.block_size = 4096;
	int r = ioctl(lfd, LOOP_CONFIGURE, &cfg);
	if (r) {
		cfg.block_size = 0;
		r = ioctl(lfd, LOOP_CONFIGURE, &cfg);
	}
	close(ffd);
	close(lfd);
	return r;
}

static int try_mount(const char *dev, const char *dir, const char *types, unsigned long fl, const char *opts)
{
	char t[128];
	snprintf(t, sizeof t, "%s", types);
	for (char *s = strtok(t, ","); s; s = strtok(NULL, ","))
		if (mount(dev, dir, s, fl, opts) == 0) return 0;
	return -1;
}

static int copy_file(const char *src, const char *dst)
{
	int in = open(src, O_RDONLY | O_CLOEXEC), out = open(dst, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
	if (in < 0 || out < 0) return -1;
	char buf[1 << 16];
	ssize_t n;
	while ((n = read(in, buf, sizeof buf)) > 0)
		if (write(out, buf, n) != n) { n = -1; break; }
	close(in); close(out);
	return n < 0 ? -1 : 0;
}

static int setup_live(const char *media)
{
	mkdir_p("/run/media", 0755);
	if (try_mount(media, "/run/media", "iso9660,vfat,ext4", MS_RDONLY, NULL)) return -1;
	const char *img = "/run/media/kwick/root.erofs";
	if (access(img, R_OK)) { umount("/run/media"); return -1; }
	mkdir_p("/run/rw", 0755);
	mount("tmpfs", "/run/rw", "tmpfs", 0, "mode=0755");
	if (cmdline_get("kwick.toram")) {
		if (copy_file(img, "/run/rw/root.erofs") == 0) { img = "/run/rw/root.erofs"; }
	}
	char loopdev[32];
	mkdir_p("/run/lower", 0755);
	if (loop_attach(img, loopdev, sizeof loopdev) ||
	    try_mount(loopdev, "/run/lower", "erofs,squashfs", MS_RDONLY, NULL)) {
		say("live: cannot mount %s: %s", img, strerror(errno));
		umount2("/run/rw", MNT_DETACH);
		umount2("/run/media", MNT_DETACH);
		return -1;
	}
	char pdev[64];
	if (resolve_dev("PARTLABEL=kwick-persist", pdev, sizeof pdev) || resolve_dev("LABEL=kwick-persist", pdev, sizeof pdev)) {
		umount("/run/rw");
		if (mount(pdev, "/run/rw", "ext4", 0, NULL)) mount("tmpfs", "/run/rw", "tmpfs", 0, "mode=0755");
	}
	mkdir_p("/run/rw/upper", 0755);
	mkdir_p("/run/rw/work", 0755);
	return mount("overlay", "/newroot", "overlay", 0,
		     "lowerdir=/run/lower,upperdir=/run/rw/upper,workdir=/run/rw/work");
}

static void stage0_fail(void)
{
	const char *p = cmdline_get("panic");
	int secs = p ? atoi(p) : 0;
	if (secs <= 0) {
		say("waiting forever (pass panic=N to reboot after N seconds)");
		for (;;) pause();
	}
	say("rebooting in %d seconds (panic=%d)", secs, secs);
	sync();
	sleep(secs);
	reboot(RB_AUTOBOOT);
	for (;;) pause();
}

static void stage0_watchdog(void)
{
	char buf[16];
	const char *v = cmdline_get("kwick.watchdog");
	if (!v && read_file("/kwick-watchdog", buf, sizeof buf) > 0) v = buf;
	int timeout = v ? atoi(v) : 0;
	if (timeout <= 0) return;
	int fd = -1;
	for (int i = 0; i < 50 && fd < 0; i++) {
		fd = open("/dev/watchdog", O_WRONLY | O_CLOEXEC);
		if (fd < 0) usleep(100000);
	}
	if (fd < 0) { say("watchdog: /dev/watchdog not available"); return; }
	ioctl(fd, WDIOC_SETTIMEOUT, &timeout);
	ioctl(fd, WDIOC_KEEPALIVE, 0);
	say("watchdog armed, %d s timeout", timeout);
	pid_t pid = fork();
	if (pid == 0) {
		int period = timeout / 4 > 0 ? timeout / 4 : 1;
		for (int t = 0; t < 150; t += period) {
			ioctl(fd, WDIOC_KEEPALIVE, 0);
			sleep(period);
		}
		ioctl(fd, WDIOC_KEEPALIVE, 0);
		_exit(0);
	}
	close(fd);
}

static void stage0(void)
{
	mount("devtmpfs", "/dev", "devtmpfs", 0, "mode=0755");
	mount("proc", "/proc", "proc", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL);
	mount("sysfs", "/sys", "sysfs", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL);
	mkdir_p("/newroot", 0755);
	mkdir_p("/run", 0755);
	mount("tmpfs", "/run", "tmpfs", MS_NOSUID | MS_NODEV, "mode=0755");
	stage0_watchdog();

	static char rootb[256], fstypeb[64], flagsb[256];
	const char *root = cmdline_dup("root", rootb, sizeof rootb);
	const char *fstype = cmdline_dup("rootfstype", fstypeb, sizeof fstypeb);
	const char *flags = cmdline_dup("rootflags", flagsb, sizeof flagsb);
	int ro = cmdline_get("ro") != NULL;
	char spec[256];
	snprintf(spec, sizeof spec, "%s", root ? root : "");
	char dev[256];
	int mounted = 0;
	long deadline = now_ms(CLOCK_MONOTONIC) + (cmdline_get("rootdelay") ? atoi(cmdline_get("rootdelay")) * 1000L : 15000L);
	for (int attempt = 0; !mounted; attempt++) {
		if (spec[0]) {
			if (!strncmp(spec, "virtiofs:", 9) || !strcmp(fstype ? fstype : "", "virtiofs")) {
				const char *tag = !strncmp(spec, "virtiofs:", 9) ? spec + 9 : spec;
				mounted = mount(tag, "/newroot", "virtiofs", ro ? MS_RDONLY : 0, flags) == 0;
			} else if (!strcmp(fstype ? fstype : "", "9p")) {
				mounted = mount(spec, "/newroot", "9p", ro ? MS_RDONLY : 0,
						flags ? flags : "trans=virtio,version=9p2000.L,msize=262144") == 0;
			} else if (resolve_dev(spec, dev, sizeof dev)) {
				mounted = try_mount(dev, "/newroot", fstype ? fstype : "ext4,erofs,btrfs,xfs,f2fs,vfat",
						    ro ? MS_RDONLY : 0, flags) == 0;
			}
		} else {
			if (cmdline_get("kwick.live") && resolve_dev("LABEL=KWICKOS", dev, sizeof dev) && setup_live(dev) == 0)
				mounted = 1;
			else if (resolve_dev("PARTLABEL=kwick-root", dev, sizeof dev) &&
			    try_mount(dev, "/newroot", "ext4,erofs,btrfs,xfs", ro ? MS_RDONLY : 0, flags) == 0)
				mounted = 1;
			else if (resolve_dev("LABEL=KWICKOS", dev, sizeof dev) && setup_live(dev) == 0)
				mounted = 1;
		}
		if (mounted) break;
		if (now_ms(CLOCK_MONOTONIC) > deadline) {
			say("no root filesystem found (root=%s); check your boot media.", spec[0] ? spec : "auto");
			stage0_fail();
		}
		if (attempt == 40) say("waiting for root device %s ...", spec[0] ? spec : "(auto)");
		usleep(25000);
	}
	umount2("/proc", MNT_DETACH);
	umount2("/sys", MNT_DETACH);
	mkdir("/newroot/dev", 0755);
	if (mount("/dev", "/newroot/dev", NULL, MS_MOVE, NULL)) umount2("/dev", MNT_DETACH);
	mkdir("/newroot/run", 0755);
	if (mount("/run", "/newroot/run", NULL, MS_MOVE, NULL)) umount2("/run", MNT_DETACH);
	unlink("/init");
	if (chdir("/newroot") || mount(".", "/", NULL, MS_MOVE, NULL) || chroot(".") || chdir("/")) {
		say("switch_root failed: %s", strerror(errno));
		stage0_fail();
	}
	const char *init = cmdline_get("init");
	execl(init ? init : "/sbin/init", "init", (char *)NULL);
	execl("/bin/sh", "sh", (char *)NULL);
	say("cannot exec init: %s", strerror(errno));
	stage0_fail();
}

enum { T_SIMPLE, T_FORKING, T_ONESHOT };
enum { R_NO, R_ONFAIL, R_ALWAYS };
enum { S_STOPPED, S_STARTING, S_RUNNING, S_EXITED, S_FAILED, S_STOPPING };
static const char *state_names[] = { "inactive", "activating", "active", "active", "failed", "deactivating" };

struct svc {
	char name[96];
	char path[PATH_MAX];
	char desc[128];
	int type, restart, remain, ignore_main_fail;
	char *start[MAX_EXEC]; int nstart;
	char *pre[MAX_EXEC]; int npre;
	char *post[MAX_EXEC]; int npost;
	char *stop, *reload;
	char user[64], group[64], workdir[256], pidfile[256];
	char *env[MAX_ENV]; int nenv;
	char *envfiles[8]; int nenvfiles;
	char *cond[16]; int ncond;
	char rtdir[128], statedir[128], logsdir[128], cachedir[128];
	int want;
	int state;
	pid_t pid;
	pid_t sid;
	int forking_wait;
	long restart_at;
	int fails;
	int exit_code;
	time_t since;
	int loaded;
	int start_after_stop;
	long kill_at;
	long started_bt;
};

static struct svc *svcs[MAX_SVC];
static int nsvc;

static void free_svc(struct svc *s)
{
	for (int i = 0; i < s->nstart; i++) free(s->start[i]);
	for (int i = 0; i < s->npre; i++) free(s->pre[i]);
	for (int i = 0; i < s->npost; i++) free(s->post[i]);
	for (int i = 0; i < s->nenv; i++) free(s->env[i]);
	for (int i = 0; i < s->nenvfiles; i++) free(s->envfiles[i]);
	for (int i = 0; i < s->ncond; i++) free(s->cond[i]);
	free(s->stop); free(s->reload);
	free(s);
}

static int find_unit_file(const char *name, char *out, size_t sz)
{
	for (int i = 0; unit_dirs[i]; i++) {
		snprintf(out, sz, "%s/%s", unit_dirs[i], name);
		if (access(out, R_OK) == 0) return 1;
	}
	const char *at = strchr(name, '@'), *dot = strrchr(name, '.');
	if (at && dot && dot > at) {
		char tmpl[128];
		snprintf(tmpl, sizeof tmpl, "%.*s@%s", (int)(at - name), name, dot);
		for (int i = 0; unit_dirs[i]; i++) {
			snprintf(out, sz, "%s/%s", unit_dirs[i], tmpl);
			if (access(out, R_OK) == 0) return 1;
		}
	}
	return 0;
}

static char *expand_spec(const char *v, const char *name)
{
	char inst[96] = "", prefix[96];
	const char *at = strchr(name, '@'), *dot = strrchr(name, '.');
	snprintf(prefix, sizeof prefix, "%.*s", (int)((at ? at : dot ? dot : name + strlen(name)) - name), name);
	if (at && dot) snprintf(inst, sizeof inst, "%.*s", (int)(dot - at - 1), at + 1);
	size_t cap = strlen(v) * 2 + 256, o = 0;
	char *r = malloc(cap);
	for (const char *p = v; *p && o < cap - 100; p++) {
		if (*p == '%' && p[1]) {
			const char *rep = NULL;
			switch (*++p) {
			case 'i': case 'I': rep = inst; break;
			case 'n': rep = name; break;
			case 'N': case 'p': case 'P': rep = prefix; break;
			case 't': rep = "/run"; break;
			case 'S': rep = "/var/lib"; break;
			case 'C': rep = "/var/cache"; break;
			case 'L': rep = "/var/log"; break;
			case 'h': rep = "/root"; break;
			case '%': rep = "%"; break;
			default: rep = ""; break;
			}
			size_t l = strlen(rep);
			if (o + l < cap - 1) { memcpy(r + o, rep, l); o += l; }
		} else r[o++] = *p;
	}
	r[o] = 0;
	return r;
}

static void add_exec(char **arr, int *n, const char *v, struct svc *s, int is_main)
{
	if (!*v) { for (int i = 0; i < *n; i++) free(arr[i]); *n = 0; return; }
	if (!is_main) { if (*n < MAX_EXEC) arr[(*n)++] = expand_spec(v, s->name); return; }
	while (*v == '-' || *v == '@' || *v == '+' || *v == '!' || *v == ':') {
		if (*v == '-') s->ignore_main_fail = 1;
		v++;
	}
	if (*n < MAX_EXEC) arr[(*n)++] = expand_spec(v, s->name);
}

static void parse_env_assign(struct svc *s, char *v)
{
	while (*v) {
		while (isspace((unsigned char)*v)) v++;
		if (!*v) break;
		char tok[1024]; size_t o = 0;
		if (*v == '"' || *v == '\'') {
			char q = *v++;
			while (*v && *v != q && o < sizeof tok - 1) tok[o++] = *v++;
			if (*v) v++;
		} else while (*v && !isspace((unsigned char)*v) && o < sizeof tok - 1) tok[o++] = *v++;
		tok[o] = 0;
		if (strchr(tok, '=') && s->nenv < MAX_ENV) s->env[s->nenv++] = expand_spec(tok, s->name);
	}
}

static void parse_unit_file(void *p, const char *path)
{
	struct svc *s = p;
	FILE *f = fopen(path, "re");
	if (!f) return;
	char line[4096], acc[8192];
	char section[64] = "";
	acc[0] = 0;
	while (fgets(line, sizeof line, f)) {
		char *l = trim(line);
		size_t ll = strlen(l);
		if (ll && l[ll - 1] == '\\') { l[ll - 1] = ' '; strncat(acc, l, sizeof acc - strlen(acc) - 1); continue; }
		strncat(acc, l, sizeof acc - strlen(acc) - 1);
		l = trim(acc);
		if (!*l || *l == '#' || *l == ';') { acc[0] = 0; continue; }
		if (*l == '[') { snprintf(section, sizeof section, "%s", l); acc[0] = 0; continue; }
		char *eq = strchr(l, '=');
		if (!eq) { acc[0] = 0; continue; }
		*eq = 0;
		char *k = trim(l), *v = trim(eq + 1);
		if (!strcmp(section, "[Unit]")) {
			if (!strcmp(k, "Description")) snprintf(s->desc, sizeof s->desc, "%s", v);
			else if (!strncmp(k, "Condition", 9)) {
				if (!*v) { for (int i = 0; i < s->ncond; i++) free(s->cond[i]); s->ncond = 0; }
				else if (s->ncond < 16) {
					size_t n = strlen(k) + strlen(v) + 2;
					s->cond[s->ncond] = malloc(n);
					snprintf(s->cond[s->ncond++], n, "%s=%s", k, v);
				}
			}
		} else if (!strcmp(section, "[Service]")) {
			if (!strcmp(k, "Type")) s->type = !strcmp(v, "forking") ? T_FORKING : !strcmp(v, "oneshot") ? T_ONESHOT : T_SIMPLE;
			else if (!strcmp(k, "ExecStart")) add_exec(s->start, &s->nstart, v, s, 1);
			else if (!strcmp(k, "ExecStartPre")) add_exec(s->pre, &s->npre, v, s, 0);
			else if (!strcmp(k, "ExecStartPost")) add_exec(s->post, &s->npost, v, s, 0);
			else if (!strcmp(k, "ExecStop")) { free(s->stop); s->stop = *v ? expand_spec(v + strspn(v, "-@+!"), s->name) : NULL; }
			else if (!strcmp(k, "ExecReload")) { free(s->reload); s->reload = *v ? expand_spec(v + strspn(v, "-@+!"), s->name) : NULL; }
			else if (!strcmp(k, "Restart")) s->restart = !strcmp(v, "always") ? R_ALWAYS : !strcmp(v, "no") ? R_NO : R_ONFAIL;
			else if (!strcmp(k, "RemainAfterExit")) s->remain = !strcmp(v, "yes") || !strcmp(v, "true") || !strcmp(v, "1");
			else if (!strcmp(k, "User")) snprintf(s->user, sizeof s->user, "%s", v);
			else if (!strcmp(k, "Group")) snprintf(s->group, sizeof s->group, "%s", v);
			else if (!strcmp(k, "DynamicUser") && !strcmp(v, "yes") && !s->user[0]) snprintf(s->user, sizeof s->user, "nobody");
			else if (!strcmp(k, "WorkingDirectory")) snprintf(s->workdir, sizeof s->workdir, "%s", v + (*v == '-'));
			else if (!strcmp(k, "PIDFile")) { char *e = expand_spec(v, s->name); snprintf(s->pidfile, sizeof s->pidfile, "%s", e); free(e); }
			else if (!strcmp(k, "Environment")) parse_env_assign(s, v);
			else if (!strcmp(k, "EnvironmentFile") && s->nenvfiles < 8) s->envfiles[s->nenvfiles++] = strdup(v);
			else if (!strcmp(k, "RuntimeDirectory")) snprintf(s->rtdir, sizeof s->rtdir, "%s", v);
			else if (!strcmp(k, "StateDirectory")) snprintf(s->statedir, sizeof s->statedir, "%s", v);
			else if (!strcmp(k, "LogsDirectory")) snprintf(s->logsdir, sizeof s->logsdir, "%s", v);
			else if (!strcmp(k, "CacheDirectory")) snprintf(s->cachedir, sizeof s->cachedir, "%s", v);
		}
		acc[0] = 0;
	}
	fclose(f);
}

static void parse_dropins(const char *name, void (*fn)(void *, const char *), void *ctx)
{
	for (int i = 0; unit_dirs[i]; i++) {
		char dd[PATH_MAX];
		snprintf(dd, sizeof dd, "%s/%s.d", unit_dirs[i], name);
		DIR *d = opendir(dd);
		if (!d) continue;
		struct dirent *de;
		while ((de = readdir(d))) {
			size_t l = strlen(de->d_name);
			if (l > 5 && !strcmp(de->d_name + l - 5, ".conf")) {
				char p[PATH_MAX + 300];
				snprintf(p, sizeof p, "%s/%s", dd, de->d_name);
				fn(ctx, p);
			}
		}
		closedir(d);
	}
}

static struct svc *load_unit(const char *name)
{
	char path[PATH_MAX];
	if (!find_unit_file(name, path, sizeof path)) return NULL;
	char rp[PATH_MAX];
	if (realpath(path, rp) && !strcmp(rp, "/dev/null")) return NULL;
	struct svc *s = calloc(1, sizeof *s);
	snprintf(s->name, sizeof s->name, "%s", name);
	snprintf(s->path, sizeof s->path, "%s", path);
	s->restart = R_NO;
	parse_unit_file(s, path);
	parse_dropins(name, parse_unit_file, s);
	if (!s->nstart) { free_svc(s); return NULL; }
	if (s->type == T_ONESHOT && s->restart == R_ALWAYS) s->restart = R_NO;
	s->loaded = 1;
	return s;
}

static struct svc *svc_loaded(const char *name)
{
	char full[128];
	snprintf(full, sizeof full, "%s%s", name, strchr(name, '.') ? "" : ".service");
	for (int i = 0; i < nsvc; i++)
		if (!strcmp(svcs[i]->name, full)) return svcs[i];
	return NULL;
}

static struct svc *svc_find(const char *name)
{
	struct svc *f = svc_loaded(name);
	if (f) return f;
	char full[128];
	snprintf(full, sizeof full, "%s%s", name, strchr(name, '.') ? "" : ".service");
	if (nsvc >= MAX_SVC) return NULL;
	struct svc *s = load_unit(full);
	if (s) svcs[nsvc++] = s;
	return s;
}

static void apply_env_file(const char *spec)
{
	int optional = spec[0] == '-';
	FILE *f = fopen(spec + optional, "re");
	if (!f) return;
	char line[2048];
	while (fgets(line, sizeof line, f)) {
		char *l = trim(line);
		if (!*l || *l == '#') continue;
		if (!strncmp(l, "export ", 7)) l += 7;
		char *eq = strchr(l, '=');
		if (!eq) continue;
		*eq = 0;
		char *v = eq + 1;
		size_t vl = strlen(v);
		if (vl >= 2 && (v[0] == '"' || v[0] == '\'') && v[vl - 1] == v[0]) { v[vl - 1] = 0; v++; }
		setenv(trim(l), v, 1);
	}
	fclose(f);
}

static void make_owned_dirs(const char *base, const char *list, uid_t uid, gid_t gid)
{
	if (!list[0]) return;
	char tmp[256];
	snprintf(tmp, sizeof tmp, "%s", list);
	for (char *t = strtok(tmp, " "); t; t = strtok(NULL, " ")) {
		char p[PATH_MAX];
		snprintf(p, sizeof p, "%s/%s", base, t);
		mkdir_p(p, 0755);
		if (chown(p, uid, gid)) { }
	}
}

static int open_log(const char *name)
{
	char p[PATH_MAX];
	mkdir_p(LOG_DIR, 0755);
	snprintf(p, sizeof p, LOG_DIR "/%s.log", name);
	struct stat st;
	if (stat(p, &st) == 0 && st.st_size > (1 << 20)) {
		char old[PATH_MAX + 4];
		snprintf(old, sizeof old, "%s.1", p);
		rename(p, old);
	}
	return open(p, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0640);
}

static int sh_run_as(const char *cmd, int drop, const char *user, uid_t uid, gid_t gid)
{
	pid_t p = fork();
	if (p < 0) return 1;
	if (p == 0) {
		child_signals();
		if (drop) {
			if (user) initgroups(user, gid); else setgroups(0, NULL);
			if (setgid(gid) || setuid(uid)) _exit(216);
		}
		execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
		_exit(127);
	}
	int st;
	while (waitpid(p, &st, 0) < 0) if (errno != EINTR) return 1;
	return WIFEXITED(st) ? WEXITSTATUS(st) : 1;
}

static int sh_run(const char *cmd)
{
	return sh_run_as(cmd, 0, NULL, 0, 0);
}

static void svc_child(struct svc *s)
{
	sigset_t all;
	sigemptyset(&all);
	sigprocmask(SIG_SETMASK, &all, NULL);
	for (int i = 1; i < 32; i++) signal(i, SIG_DFL);
	setsid();
	int nul = open("/dev/null", O_RDONLY);
	if (nul >= 0) { dup2(nul, 0); if (nul > 0) close(nul); }
	int lf = open_log(s->name);
	if (lf >= 0) { dup2(lf, 1); dup2(lf, 2); if (lf > 2) close(lf); }
	clearenv();
	setenv("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", 1);
	setenv("LANG", "C.UTF-8", 1);
	for (int i = 0; i < s->nenvfiles; i++) apply_env_file(s->envfiles[i]);
	for (int i = 0; i < s->nenv; i++) putenv(s->env[i]);
	uid_t uid = 0; gid_t gid = 0;
	struct passwd *pw = s->user[0] ? getpwnam(s->user) : NULL;
	if (s->user[0] && !pw) {
		if (isdigit((unsigned char)s->user[0])) { uid = atoi(s->user); gid = uid; }
		else { dprintf(2, "kinit: unknown user %s\n", s->user); _exit(217); }
	}
	if (pw) { uid = pw->pw_uid; gid = pw->pw_gid; setenv("HOME", pw->pw_dir, 1); setenv("USER", pw->pw_name, 1); }
	else setenv("HOME", "/root", 1);
	if (s->group[0]) { struct group *gr = getgrnam(s->group); if (gr) gid = gr->gr_gid; }
	make_owned_dirs("/run", s->rtdir, uid, gid);
	make_owned_dirs("/var/lib", s->statedir, uid, gid);
	make_owned_dirs("/var/log", s->logsdir, uid, gid);
	make_owned_dirs("/var/cache", s->cachedir, uid, gid);
	if (s->rtdir[0]) { char p[300]; snprintf(p, sizeof p, "/run/%s", strtok(s->rtdir, " ")); setenv("RUNTIME_DIRECTORY", p, 1); }
	char uname[64] = "";
	if (pw) snprintf(uname, sizeof uname, "%s", pw->pw_name);
	int drop = s->user[0] || s->group[0];
	for (int i = 0; i < s->npre; i++) {
		const char *c = s->pre[i];
		size_t k = strspn(c, "-@+!:");
		int ign = memchr(c, '-', k) != NULL, priv = memchr(c, '+', k) || memchr(c, '!', k);
		int r = sh_run_as(c + k, drop && !priv, uname[0] ? uname : NULL, uid, gid);
		if (r && !ign) { dprintf(2, "kinit: ExecStartPre failed (%d): %s\n", r, c + k); _exit(r); }
	}
	if (drop) {
		if (uname[0]) initgroups(uname, gid); else setgroups(0, NULL);
		if (setgid(gid) || setuid(uid)) _exit(216);
	}
	if (s->workdir[0] && chdir(s->workdir[0] == '~' ? getenv("HOME") : s->workdir)) _exit(200);
	if (s->type == T_ONESHOT) {
		for (int i = 0; i < s->nstart; i++) { int r = sh_run(s->start[i]); if (r && !s->ignore_main_fail) _exit(r); }
		_exit(0);
	}
	char cmd[8192];
	snprintf(cmd, sizeof cmd, "exec %s", s->start[0]);
	execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
	_exit(127);
}

static int dir_has_entries(const char *path)
{
	DIR *d = opendir(path);
	if (!d) return 0;
	struct dirent *de;
	int any = 0;
	while (!any && (de = readdir(d))) any = strcmp(de->d_name, ".") && strcmp(de->d_name, "..");
	closedir(d);
	return any;
}

static int needs_update(const char *dir)
{
	char p[PATH_MAX];
	struct stat u, d;
	snprintf(p, sizeof p, "%s/.updated", dir);
	if (stat("/usr", &u)) return 0;
	if (stat(p, &d)) return 1;
	return u.st_mtim.tv_sec > d.st_mtim.tv_sec ||
		(u.st_mtim.tv_sec == d.st_mtim.tv_sec && u.st_mtim.tv_nsec > d.st_mtim.tv_nsec);
}

static int cond_true(const char *k, const char *v)
{
	struct stat st;
	if (!strcmp(k, "ConditionPathExists")) return access(v, F_OK) == 0;
	if (!strcmp(k, "ConditionPathIsDirectory")) return stat(v, &st) == 0 && S_ISDIR(st.st_mode);
	if (!strcmp(k, "ConditionPathIsSymbolicLink")) return lstat(v, &st) == 0 && S_ISLNK(st.st_mode);
	if (!strcmp(k, "ConditionPathIsReadWrite")) return access(v, W_OK) == 0;
	if (!strcmp(k, "ConditionDirectoryNotEmpty")) return dir_has_entries(v);
	if (!strcmp(k, "ConditionFileNotEmpty")) return stat(v, &st) == 0 && S_ISREG(st.st_mode) && st.st_size > 0;
	if (!strcmp(k, "ConditionFileIsExecutable")) return stat(v, &st) == 0 && S_ISREG(st.st_mode) && (st.st_mode & 0111);
	if (!strcmp(k, "ConditionNeedsUpdate")) return needs_update(v);
	if (!strcmp(k, "ConditionKernelCommandLine")) {
		char key[256];
		snprintf(key, sizeof key, "%s", v);
		char *eq = strchr(key, '=');
		if (eq) *eq = 0;
		const char *got = cmdline_get(key);
		return eq ? got && !strcmp(got, eq + 1) : got != NULL;
	}
	if (!strcmp(k, "ConditionFirstBoot")) {
		int first = stat("/etc/machine-id", &st) || st.st_size == 0;
		return first == (!strcmp(v, "yes") || !strcmp(v, "true") || !strcmp(v, "1"));
	}
	return 1;
}

static int conds_met(const struct svc *s)
{
	int trig = 0, trig_ok = 0;
	for (int i = 0; i < s->ncond; i++) {
		char k[64];
		const char *eq = strchr(s->cond[i], '=');
		snprintf(k, sizeof k, "%.*s", (int)(eq - s->cond[i]), s->cond[i]);
		const char *v = eq + 1;
		int is_trig = *v == '|';
		v += is_trig;
		int neg = *v == '!';
		v += neg;
		int r = cond_true(k, v) != neg;
		if (is_trig) { trig = 1; trig_ok |= r; }
		else if (!r) return 0;
	}
	return !trig || trig_ok;
}

static void svc_start(struct svc *s)
{
	if (s->state == S_RUNNING || s->state == S_STARTING) return;
	s->want = 1;
	if (s->state == S_STOPPING) { s->start_after_stop = 1; return; }
	if (!conds_met(s)) {
		s->state = s->remain ? S_EXITED : S_STOPPED;
		if (verbose) say("skipped %s (condition not met)", s->name);
		return;
	}
	pid_t p = fork();
	if (p < 0) { s->state = S_FAILED; return; }
	if (p == 0) svc_child(s);
	s->restart_at = 0;
	s->pid = p;
	s->sid = p;
	s->state = S_STARTING;
	s->forking_wait = s->type == T_FORKING;
	s->since = time(NULL);
	s->started_bt = now_ms(CLOCK_BOOTTIME);
	if (s->type == T_SIMPLE) s->state = S_RUNNING;
	if (verbose) say("started %s (pid %d)", s->name, p);
	for (int i = 0; i < s->npost; i++) sh_run(s->post[i] + strspn(s->post[i], "-@+!:"));
}

static int proc_uid_is(pid_t p, uid_t uid)
{
	char path[64], b[2048];
	snprintf(path, sizeof path, "/proc/%d/status", (int)p);
	if (read_file(path, b, sizeof b) <= 0) return 0;
	char *u = strstr(b, "\nUid:");
	if (!u) return 0;
	unsigned long id[4];
	if (sscanf(u + 5, "%lu %lu %lu %lu", &id[0], &id[1], &id[2], &id[3]) != 4) return 0;
	for (int i = 0; i < 4; i++) if (id[i] != (unsigned long)uid) return 0;
	return 1;
}

static pid_t read_pidfile(struct svc *s)
{
	char b[32];
	if (!s->pidfile[0]) return 0;
	int fd = open(s->pidfile, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
	if (fd < 0) return 0;
	struct stat st;
	ssize_t n = -1;
	if (fstat(fd, &st) == 0 && S_ISREG(st.st_mode)) n = read(fd, b, sizeof b - 1);
	close(fd);
	if (n <= 0) return 0;
	b[n] = 0;
	char *end;
	long v = strtol(b, &end, 10);
	while (*end == ' ' || *end == '\t' || *end == '\n' || *end == '\r') end++;
	if (*end || v <= 1 || v > INT_MAX) return 0;
	pid_t p = (pid_t)v;
	if (kill(p, 0) < 0 && errno == ESRCH) return 0;
	int trusted = st.st_uid == 0 && !(st.st_mode & (S_IWGRP | S_IWOTH));
	if (trusted) return p;
	if (s->sid > 0 && (getsid(p) == s->sid || getpgid(p) == s->sid)) return p;
	if (st.st_uid != 0 && !(st.st_mode & (S_IWGRP | S_IWOTH)) && proc_uid_is(p, st.st_uid)) return p;
	say("%s: ignoring PID file %s, pid %d is not part of the service", s->name, s->pidfile, (int)p);
	return -1;
}

static void svc_stopped(struct svc *s)
{
	s->pid = 0;
	s->state = S_STOPPED;
	s->kill_at = 0;
	if (s->start_after_stop) { s->start_after_stop = 0; svc_start(s); }
}

static void svc_stop(struct svc *s)
{
	s->want = 0;
	s->restart_at = 0;
	s->start_after_stop = 0;
	if (s->state == S_STOPPING) return;
	if (s->stop && (s->state == S_RUNNING || s->state == S_EXITED)) {
		char envmp[64];
		snprintf(envmp, sizeof envmp, "%d", s->pid);
		setenv("MAINPID", envmp, 1);
		sh_run(s->stop);
		unsetenv("MAINPID");
	}
	if (s->pid > 0 && (s->state == S_RUNNING || s->state == S_STARTING)) {
		kill(-s->pid, SIGTERM);
		kill(s->pid, SIGTERM);
		kill(s->pid, SIGCONT);
		s->state = S_STOPPING;
		s->kill_at = now_ms(CLOCK_MONOTONIC) + 5000;
		return;
	}
	s->pid = 0;
	s->state = S_STOPPED;
}

static int stop_tick(long now)
{
	int wait = 5000;
	for (int i = 0; i < nsvc; i++) {
		struct svc *s = svcs[i];
		if (s->state != S_STOPPING) continue;
		if (s->pid <= 0 || kill(s->pid, 0) < 0) { svc_stopped(s); continue; }
		if (now >= s->kill_at) { kill(-s->pid, SIGKILL); kill(s->pid, SIGKILL); svc_stopped(s); continue; }
		wait = 100;
	}
	return wait;
}

static void svc_exited(struct svc *s, int st)
{
	int code = WIFEXITED(st) ? WEXITSTATUS(st) : 128 + WTERMSIG(st);
	s->exit_code = code;
	if (s->state == S_STOPPING) { s->forking_wait = 0; svc_stopped(s); return; }
	if (s->forking_wait) {
		s->forking_wait = 0;
		if (code == 0) {
			pid_t mp = 0;
			for (int i = 0; i < 40 && !(mp = read_pidfile(s)); i++) usleep(25000);
			s->pid = mp > 0 ? mp : 0;
			s->state = S_RUNNING;
			return;
		}
	}
	if (s->type == T_ONESHOT && code == 0) { s->state = s->remain ? S_EXITED : S_STOPPED; s->pid = 0; return; }
	s->pid = 0;
	if (!s->want) { s->state = S_STOPPED; return; }
	s->state = (code == 0 || s->ignore_main_fail) ? S_STOPPED : S_FAILED;
	if (s->restart == R_ALWAYS || (s->restart == R_ONFAIL && code != 0)) {
		if (time(NULL) - s->since >= 30) s->fails = 0;
		if (++s->fails > 10) { say("%s keeps exiting, not restarting it again", s->name); return; }
		long delay = s->fails > 5 ? 5000 : 100L << s->fails;
		s->restart_at = now_ms(CLOCK_MONOTONIC) + delay;
	}
}

static int is_enabled(const char *name, char *target_out, size_t tsz)
{
	DIR *d = opendir("/etc/systemd/system");
	if (!d) return 0;
	struct dirent *de;
	int en = 0;
	while (!en && (de = readdir(d))) {
		size_t l = strlen(de->d_name);
		if (l < 7 || strcmp(de->d_name + l - 6, ".wants")) continue;
		char p[PATH_MAX];
		snprintf(p, sizeof p, "/etc/systemd/system/%s/%s", de->d_name, name);
		if (access(p, F_OK) == 0 || faccessat(AT_FDCWD, p, F_OK, AT_SYMLINK_NOFOLLOW) == 0) {
			en = 1;
			if (target_out) snprintf(target_out, tsz, "%.*s", (int)(l - 6), de->d_name);
		}
	}
	closedir(d);
	return en;
}

static const char *boot_wants[] = { "sysinit.target.wants", "basic.target.wants",
	"network.target.wants", "network-online.target.wants", "multi-user.target.wants",
	"default.target.wants", "getty.target.wants", "timers.target.wants", NULL };

static void load_boot_units(void)
{
	for (int t = 0; boot_wants[t]; t++) {
		for (int i = 0; unit_dirs[i]; i++) {
			char dd[PATH_MAX];
			snprintf(dd, sizeof dd, "%s/%s", unit_dirs[i], boot_wants[t]);
			DIR *d = opendir(dd);
			if (!d) continue;
			struct dirent *de;
			while ((de = readdir(d))) {
				size_t l = strlen(de->d_name);
				if (l < 9 || strcmp(de->d_name + l - 8, ".service")) continue;
				struct svc *s = svc_find(de->d_name);
				if (s) s->want = 1;
			}
			closedir(d);
		}
	}
}

static volatile int shutdown_req;
static int sfd = -1, ctlfd = -1, uevfd = -1;
static long boot_ready_ms;

#define MAX_TIMER 64
#define TIMER_DIR "/var/lib/kinit/timers"

struct cal { uint64_t sec, min; uint32_t hour, day; uint16_t mon; uint8_t dow; };

struct tmr {
	char name[96], unit[96], desc[128], path[PATH_MAX];
	struct cal cal[4];
	int ncal, persistent, manual, seen, boot_done, active_done;
	long boot_ms, active_ms, unit_ms, rnd_ms, off_ms, activated_bt, last_fire_bt;
	time_t cal_next, last;
};

static struct tmr *tmrs[MAX_TIMER];
static int ntmr;

static long parse_span(const char *v)
{
	static const struct { const char *u; double ms; } units[] = {
		{ "", 1000 }, { "s", 1000 }, { "sec", 1000 }, { "second", 1000 }, { "seconds", 1000 },
		{ "ms", 1 }, { "msec", 1 }, { "us", 0.001 }, { "usec", 0.001 },
		{ "m", 60000 }, { "min", 60000 }, { "minute", 60000 }, { "minutes", 60000 },
		{ "h", 3600000 }, { "hr", 3600000 }, { "hour", 3600000 }, { "hours", 3600000 },
		{ "d", 86400000 }, { "day", 86400000 }, { "days", 86400000 },
		{ "w", 604800000 }, { "week", 604800000 }, { "weeks", 604800000 },
		{ "M", 2629800000.0 }, { "month", 2629800000.0 }, { "months", 2629800000.0 },
		{ "y", 31557600000.0 }, { "year", 31557600000.0 }, { "years", 31557600000.0 }, { NULL, 0 } };
	double total = 0;
	int any = 0;
	while (*v) {
		while (isspace((unsigned char)*v)) v++;
		if (!*v) break;
		if (!isdigit((unsigned char)*v) && *v != '.') return -1;
		char *e;
		double n = strtod(v, &e);
		if (e == v) return -1;
		v = e;
		while (isspace((unsigned char)*v)) v++;
		char u[16];
		size_t o = 0;
		while (isalpha((unsigned char)*v) && o < sizeof u - 1) u[o++] = *v++;
		u[o] = 0;
		int k = 0;
		while (units[k].u && strcmp(units[k].u, u)) k++;
		if (!units[k].u) return -1;
		total += n * units[k].ms;
		any = 1;
	}
	return any && total < 1e15 ? (long)total : -1;
}

static int cal_value(const char *s, int lo, int hi, int dow, int *out)
{
	static const char *days[] = { "sun", "mon", "tue", "wed", "thu", "fri", "sat" };
	static const char *full[] = { "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday" };
	if (dow) {
		for (int i = 0; i < 7; i++)
			if (!strcasecmp(s, days[i]) || !strcasecmp(s, full[i])) { *out = i; return 0; }
		return -1;
	}
	if (!isdigit((unsigned char)*s)) return -1;
	char *e;
	long v = strtol(s, &e, 10);
	if (*e || v < lo || v > hi) return -1;
	*out = (int)v;
	return 0;
}

static int cal_field(const char *s, int lo, int hi, int dow, uint64_t *mask)
{
	char tmp[128], *save;
	snprintf(tmp, sizeof tmp, "%s", s);
	*mask = 0;
	for (char *it = strtok_r(tmp, ",", &save); it; it = strtok_r(NULL, ",", &save)) {
		int a, b, step = 1;
		char *sl = strchr(it, '/');
		if (sl) {
			*sl = 0;
			char *e;
			step = (int)strtol(sl + 1, &e, 10);
			if (*e || step <= 0 || sl[1] == 0) return -1;
		}
		char *dd = strstr(it, "..");
		if (dd) *dd = 0;
		if (!strcmp(it, "*")) {
			if (dd) return -1;
			a = lo; b = hi;
		} else {
			if (cal_value(it, lo, hi, dow, &a)) return -1;
			b = sl ? hi : a;
			if (dd && cal_value(dd + 2, lo, hi, dow, &b)) return -1;
		}
		if (b < a && !dow) return -1;
		if (b < a) {
			for (int i = 0; i <= b + 7 - a; i += step) *mask |= 1ULL << ((a + i) % 7);
		} else {
			for (int v = a; v <= b; v += step) *mask |= 1ULL << v;
		}
	}
	return *mask ? 0 : -1;
}

static int parse_cal(const char *v, struct cal *c)
{
	static const char *alias[][2] = {
		{ "minutely", "*-*-* *:*:00" }, { "hourly", "*-*-* *:00:00" }, { "daily", "*-*-* 00:00:00" },
		{ "weekly", "Mon *-*-* 00:00:00" }, { "monthly", "*-*-01 00:00:00" }, { "yearly", "*-01-01 00:00:00" },
		{ "annually", "*-01-01 00:00:00" }, { "quarterly", "*-01,04,07,10-01 00:00:00" },
		{ "semiannually", "*-01,07-01 00:00:00" }, { NULL, NULL } };
	char tmp[256], *save;
	snprintf(tmp, sizeof tmp, "%s", v);
	for (int i = 0; alias[i][0]; i++)
		if (!strcasecmp(v, alias[i][0])) snprintf(tmp, sizeof tmp, "%s", alias[i][1]);
	uint64_t m;
	c->dow = 0x7f; c->mon = 0x1ffe; c->day = 0xfffffffe; c->hour = 1; c->min = 1; c->sec = 1;
	int stage = 0;
	for (char *tok = strtok_r(tmp, " \t", &save); tok; tok = strtok_r(NULL, " \t", &save)) {
		if (strchr(tok, ':') && stage <= 2) {
			char *mi = strchr(tok, ':'), *se;
			*mi++ = 0;
			se = strchr(mi, ':');
			if (se) *se++ = 0;
			if (cal_field(tok, 0, 23, 0, &m)) return -1;
			c->hour = (uint32_t)m;
			if (cal_field(mi, 0, 59, 0, &c->min)) return -1;
			if (se && cal_field(se, 0, 59, 0, &c->sec)) return -1;
			stage = 3;
		} else if (strchr(tok, '-') && stage <= 1) {
			char *p[3];
			int n = 1;
			for (char *q = tok; (q = strchr(q, '-')); q++) n++;
			if (n > 3) return -1;
			p[0] = tok;
			for (int i = 1; i < n; i++) { p[i] = strchr(p[i - 1], '-'); *p[i]++ = 0; }
			if (n == 3 && strcmp(p[0], "*")) return -1;
			if (cal_field(p[n - 2], 1, 12, 0, &m)) return -1;
			c->mon = (uint16_t)m;
			if (cal_field(p[n - 1], 1, 31, 0, &m)) return -1;
			c->day = (uint32_t)m;
			stage = 2;
		} else if (isalpha((unsigned char)tok[0]) && stage == 0) {
			if (cal_field(tok, 0, 6, 1, &m)) return -1;
			c->dow = (uint8_t)m;
			stage = 1;
		} else return -1;
	}
	return stage ? 0 : -1;
}

#define PLAUSIBLE_TIME 1577836800

static time_t naive_of(time_t t)
{
	struct tm tm;
	if (!localtime_r(&t, &tm)) return (time_t)-1;
	return timegm(&tm);
}

static time_t naive_next(const struct cal *c, time_t from)
{
	time_t t = from;
	struct tm tm;
	for (int i = 0; i < 20000; i++) {
		if (!gmtime_r(&t, &tm)) return (time_t)-1;
		if (!(c->mon >> (tm.tm_mon + 1) & 1)) { tm.tm_mon++; tm.tm_mday = 1; tm.tm_hour = tm.tm_min = tm.tm_sec = 0; }
		else if (!(c->day >> tm.tm_mday & 1) || !(c->dow >> tm.tm_wday & 1)) { tm.tm_mday++; tm.tm_hour = tm.tm_min = tm.tm_sec = 0; }
		else if (!(c->hour >> tm.tm_hour & 1)) { tm.tm_hour++; tm.tm_min = tm.tm_sec = 0; }
		else if (!(c->min >> tm.tm_min & 1)) { tm.tm_min++; tm.tm_sec = 0; }
		else if (!(c->sec >> tm.tm_sec & 1)) tm.tm_sec++;
		else return t;
		time_t n = timegm(&tm);
		t = n > t ? n : t + 1;
	}
	return (time_t)-1;
}

static int local_occurrences(time_t n, time_t occ[2])
{
	int k = 0;
	for (int d = 0; d < 2; d++) {
		struct tm tm;
		gmtime_r(&n, &tm);
		tm.tm_isdst = d;
		time_t v = mktime(&tm);
		if (v == (time_t)-1 || naive_of(v) != n) continue;
		if (k && occ[0] == v) continue;
		occ[k++] = v;
	}
	if (k == 2 && occ[1] < occ[0]) { time_t x = occ[0]; occ[0] = occ[1]; occ[1] = x; }
	return k;
}

static time_t gap_end(time_t n)
{
	struct tm tm;
	time_t v[2];
	for (int d = 0; d < 2; d++) {
		gmtime_r(&n, &tm);
		tm.tm_isdst = d;
		v[d] = mktime(&tm);
	}
	time_t lo = v[0] < v[1] ? v[0] : v[1], hi = v[0] < v[1] ? v[1] : v[0];
	if (lo == (time_t)-1 || naive_of(hi) <= n) return (time_t)-1;
	if (naive_of(lo) > n) return lo;
	while (hi - lo > 1) {
		time_t mid = lo + (hi - lo) / 2;
		if (naive_of(mid) > n) hi = mid; else lo = mid;
	}
	return hi;
}

static time_t next_cal(const struct cal *c, time_t after)
{
	time_t from = naive_of(after);
	if (from == (time_t)-1) return 0;
	int every_hour = (c->hour & 0xffffff) == 0xffffff;
	for (int i = 0; i < 2000; i++) {
		time_t n = naive_next(c, from);
		if (n == (time_t)-1) return 0;
		time_t occ[2];
		int k = local_occurrences(n, occ);
		if (!k) {
			time_t g = gap_end(n);
			if (g != (time_t)-1 && g > after) return g;
		} else {
			if (occ[0] > after) return occ[0];
			if (k == 2 && every_hour && occ[1] > after) return occ[1];
		}
		from = n + 1;
	}
	return 0;
}

static long timer_span(struct tmr *t, const char *k, const char *v)
{
	if (!*v) return -1;
	long r = parse_span(v);
	if (r < 0) say("%s: unsupported %s=%s, skipped", t->name, k, v);
	return r;
}

static void parse_timer_file(void *p, const char *path)
{
	struct tmr *t = p;
	FILE *f = fopen(path, "re");
	if (!f) return;
	char line[1024], section[64] = "";
	while (fgets(line, sizeof line, f)) {
		char *l = trim(line);
		if (!*l || *l == '#' || *l == ';') continue;
		if (*l == '[') { snprintf(section, sizeof section, "%s", l); continue; }
		char *eq = strchr(l, '=');
		if (!eq) continue;
		*eq = 0;
		char *k = trim(l), *v = trim(eq + 1);
		if (!strcmp(section, "[Unit]") && !strcmp(k, "Description")) snprintf(t->desc, sizeof t->desc, "%s", v);
		if (strcmp(section, "[Timer]")) continue;
		if (!strcmp(k, "OnCalendar")) {
			if (!*v) t->ncal = 0;
			else if (t->ncal < 4 && parse_cal(v, &t->cal[t->ncal]) == 0) t->ncal++;
			else say("%s: unsupported OnCalendar=%s, skipped", t->name, v);
		} else if (!strcmp(k, "OnBootSec") || !strcmp(k, "OnStartupSec")) t->boot_ms = timer_span(t, k, v);
		else if (!strcmp(k, "OnActiveSec")) t->active_ms = timer_span(t, k, v);
		else if (!strcmp(k, "OnUnitActiveSec") || !strcmp(k, "OnUnitInactiveSec")) t->unit_ms = timer_span(t, k, v);
		else if (!strcmp(k, "Persistent")) t->persistent = !strcmp(v, "yes") || !strcmp(v, "true") || !strcmp(v, "1");
		else if (!strcmp(k, "RandomizedDelaySec")) { long r = parse_span(v); t->rnd_ms = r > 0 ? r : 0; }
		else if (!strcmp(k, "Unit")) snprintf(t->unit, sizeof t->unit, "%s", v);
	}
	fclose(f);
}

static struct tmr *timer_load(const char *name)
{
	char path[PATH_MAX], rp[PATH_MAX];
	if (!find_unit_file(name, path, sizeof path)) return NULL;
	if (realpath(path, rp) && !strcmp(rp, "/dev/null")) return NULL;
	struct tmr *t = calloc(1, sizeof *t);
	snprintf(t->name, sizeof t->name, "%s", name);
	snprintf(t->path, sizeof t->path, "%s", path);
	t->boot_ms = t->active_ms = t->unit_ms = -1;
	parse_timer_file(t, path);
	parse_dropins(name, parse_timer_file, t);
	if (!t->unit[0]) snprintf(t->unit, sizeof t->unit, "%.*s.service", (int)(strlen(name) - 6), name);
	if (!t->ncal && t->boot_ms < 0 && t->active_ms < 0 && t->unit_ms < 0) {
		say("%s: no supported trigger, skipped", name);
		free(t);
		return NULL;
	}
	if (t->unit_ms >= 0 && t->unit_ms < 1000) t->unit_ms = 1000;
	if (t->rnd_ms > 0) {
		char id[64] = "";
		if (read_file("/etc/machine-id", id, sizeof id) < 0) id[0] = 0;
		uint64_t h = 1469598103934665603ULL;
		for (const char *c = trim(id); *c; c++) h = (h ^ (unsigned char)*c) * 1099511628211ULL;
		for (const char *c = name; *c; c++) h = (h ^ (unsigned char)*c) * 1099511628211ULL;
		t->off_ms = (long)(h % (uint64_t)t->rnd_ms);
	}
	return t;
}

static void timer_schedule(struct tmr *t)
{
	t->cal_next = 0;
	time_t now = time(NULL);
	time_t base = t->persistent && t->last >= PLAUSIBLE_TIME && t->last < now ? t->last : now;
	for (int i = 0; i < t->ncal; i++) {
		time_t n = next_cal(&t->cal[i], base);
		if (n && (!t->cal_next || n < t->cal_next)) t->cal_next = n;
	}
}

static void timer_activate(struct tmr *t)
{
	t->activated_bt = now_ms(CLOCK_BOOTTIME);
	if (t->persistent) {
		char p[PATH_MAX];
		struct stat st;
		snprintf(p, sizeof p, TIMER_DIR "/%s", t->name);
		time_t now = time(NULL);
		if (stat(p, &st) == 0) {
			t->last = st.st_mtime;
			if (now >= PLAUSIBLE_TIME && t->last > now) { t->last = now; utimensat(AT_FDCWD, p, NULL, 0); }
		} else { mkdir_p(TIMER_DIR, 0755); write_file(p, ""); }
	}
	timer_schedule(t);
}

static long timer_mono_due(struct tmr *t)
{
	long due = LONG_MAX;
	if (t->boot_ms >= 0 && !t->boot_done) due = t->boot_ms + t->off_ms;
	if (t->active_ms >= 0 && !t->active_done && t->activated_bt + t->active_ms + t->off_ms < due)
		due = t->activated_bt + t->active_ms + t->off_ms;
	if (t->unit_ms >= 0) {
		long base = t->last_fire_bt;
		struct svc *s = svc_loaded(t->unit);
		if (s && s->started_bt > base) base = s->started_bt;
		if (base && base + t->unit_ms + t->off_ms < due) due = base + t->unit_ms + t->off_ms;
	}
	return due;
}

static long timer_cal_due(struct tmr *t)
{
	return t->cal_next ? t->cal_next * 1000L + t->off_ms : 0;
}

static void timer_fire(struct tmr *t, long bt)
{
	t->last_fire_bt = bt;
	t->last = time(NULL);
	if (t->persistent) {
		char p[PATH_MAX];
		snprintf(p, sizeof p, TIMER_DIR "/%s", t->name);
		mkdir_p(TIMER_DIR, 0755);
		write_file(p, "");
		utimensat(AT_FDCWD, p, NULL, 0);
	}
	timer_schedule(t);
	struct svc *s = svc_find(t->unit);
	if (!s) { say("%s: unit %s not found", t->name, t->unit); return; }
	if (verbose) say("%s: starting %s", t->name, s->name);
	svc_start(s);
}

static int tz_refresh(void)
{
	static struct stat seen;
	static int known;
	struct stat st;
	if (stat("/etc/localtime", &st) != 0) memset(&st, 0, sizeof st);
	if (known && st.st_dev == seen.st_dev && st.st_ino == seen.st_ino && st.st_size == seen.st_size &&
		st.st_mtime == seen.st_mtime && st.st_ctime == seen.st_ctime) return 0;
	int first = !known;
	seen = st;
	known = 1;
	char *tz = getenv("TZ");
	char keep[256] = "";
	if (tz) snprintf(keep, sizeof keep, "%s", tz);
	setenv("TZ", "UTC0", 1);
	tzset();
	if (tz) setenv("TZ", keep, 1); else unsetenv("TZ");
	tzset();
	return !first;
}

static void timers_reschedule(void)
{
	time_t now = time(NULL);
	for (int i = 0; i < ntmr; i++) {
		if (now >= PLAUSIBLE_TIME && tmrs[i]->last > now) tmrs[i]->last = now;
		timer_schedule(tmrs[i]);
	}
}

static long timers_tick(void)
{
	static long rt_bt = LONG_MIN;
	long wait = 60000;
	if (shutdown_req) return wait;
	long bt = now_ms(CLOCK_BOOTTIME), rt = now_ms(CLOCK_REALTIME);
	int changed = tz_refresh();
	if (rt_bt != LONG_MIN && labs(rt - bt - rt_bt) > 2000) {
		if (verbose) say("clock stepped by %lds, rescheduling timers", (rt - bt - rt_bt) / 1000);
		changed = 1;
	}
	rt_bt = rt - bt;
	if (changed) timers_reschedule();
	for (int i = 0; i < ntmr; i++) {
		struct tmr *t = tmrs[i];
		long due = timer_mono_due(t), cal = timer_cal_due(t);
		if (due <= bt || (cal && cal <= rt)) {
			if (t->boot_ms >= 0 && t->boot_ms + t->off_ms <= bt) t->boot_done = 1;
			if (t->active_ms >= 0 && t->activated_bt + t->active_ms + t->off_ms <= bt) t->active_done = 1;
			timer_fire(t, bt);
			due = timer_mono_due(t);
			cal = timer_cal_due(t);
		}
		if (due != LONG_MAX && due - bt < wait) wait = due - bt;
		if (cal && cal - rt < wait) wait = cal - rt;
	}
	return wait < 0 ? 0 : wait;
}

static int timer_index(const char *name)
{
	for (int i = 0; i < ntmr; i++) if (!strcmp(tmrs[i]->name, name)) return i;
	return -1;
}

static void timer_remove(int i)
{
	free(tmrs[i]);
	memmove(tmrs + i, tmrs + i + 1, (ntmr - i - 1) * sizeof *tmrs);
	ntmr--;
}

static void timer_reload(int i)
{
	struct tmr *o = tmrs[i], *t = timer_load(o->name);
	if (!t) { o->seen = 0; o->manual = 0; return; }
	t->activated_bt = o->activated_bt; t->boot_done = o->boot_done; t->active_done = o->active_done;
	t->last_fire_bt = o->last_fire_bt; t->last = o->last; t->manual = o->manual; t->seen = 1;
	timer_schedule(t);
	tmrs[i] = t;
	free(o);
}

static void timers_scan(void)
{
	if (tz_refresh()) timers_reschedule();
	for (int i = 0; i < ntmr; i++) tmrs[i]->seen = 0;
	for (int w = 0; boot_wants[w]; w++) {
		for (int i = 0; unit_dirs[i]; i++) {
			char dd[PATH_MAX];
			snprintf(dd, sizeof dd, "%s/%s", unit_dirs[i], boot_wants[w]);
			DIR *d = opendir(dd);
			if (!d) continue;
			struct dirent *de;
			while ((de = readdir(d))) {
				size_t l = strlen(de->d_name);
				if (l < 7 || l >= 96 || strcmp(de->d_name + l - 6, ".timer")) continue;
				int k = timer_index(de->d_name);
				if (k >= 0) { if (!tmrs[k]->seen) timer_reload(k); continue; }
				if (ntmr >= MAX_TIMER) continue;
				struct tmr *t = timer_load(de->d_name);
				if (!t) continue;
				t->seen = 1;
				timer_activate(t);
				tmrs[ntmr++] = t;
			}
			closedir(d);
		}
	}
	for (int i = 0; i < ntmr; i++)
		if (!tmrs[i]->seen && tmrs[i]->manual) timer_reload(i);
	for (int i = ntmr - 1; i >= 0; i--)
		if (!tmrs[i]->seen) timer_remove(i);
}

static void fmt_span(long ms, char *b, size_t sz)
{
	long s = ms / 1000;
	if (s >= 86400) snprintf(b, sz, "%ldd %ldh", s / 86400, s % 86400 / 3600);
	else if (s >= 3600) snprintf(b, sz, "%ldh %ldmin", s / 3600, s % 3600 / 60);
	else if (s >= 60) snprintf(b, sz, "%ldmin %lds", s / 60, s % 60);
	else snprintf(b, sz, "%lds", s);
}

static void fmt_when(long rt, char *b, size_t sz)
{
	time_t tt = rt / 1000;
	struct tm tm;
	if (rt <= 0 || !localtime_r(&tt, &tm)) { snprintf(b, sz, "-"); return; }
	strftime(b, sz, "%a %Y-%m-%d %H:%M:%S %Z", &tm);
}

static long timer_next_rt(struct tmr *t, long bt, long rt)
{
	long due = timer_mono_due(t), cal = timer_cal_due(t), next = 0;
	if (due != LONG_MAX) next = rt + (due > bt ? due - bt : 0);
	if (cal && (!next || cal < next)) next = cal;
	return next;
}

static void fmt_timers(char *out, size_t sz)
{
	long bt = now_ms(CLOCK_BOOTTIME), rt = now_ms(CLOCK_REALTIME);
	int ord[MAX_TIMER];
	long nx[MAX_TIMER];
	for (int i = 0; i < ntmr; i++) {
		long v = timer_next_rt(tmrs[i], bt, rt);
		nx[i] = v ? v : LONG_MAX;
		int j = i;
		while (j > 0 && nx[ord[j - 1]] > nx[i]) { ord[j] = ord[j - 1]; j--; }
		ord[j] = i;
	}
	size_t o = snprintf(out, sz, "%-31s %-16s %-31s %-16s %-28s %s\n", "NEXT", "LEFT", "LAST", "PASSED", "UNIT", "ACTIVATES");
	for (int k = 0; k < ntmr && o < sz - 512; k++) {
		struct tmr *t = tmrs[ord[k]];
		char next[64], left[32] = "-", last[64], passed[32] = "-";
		long n = nx[ord[k]] == LONG_MAX ? 0 : nx[ord[k]];
		fmt_when(n, next, sizeof next);
		if (n) { fmt_span(n - rt, left, sizeof left - 5); strcat(left, " left"); }
		fmt_when(t->last * 1000L, last, sizeof last);
		if (t->last) { fmt_span(rt - t->last * 1000L, passed, sizeof passed - 4); strcat(passed, " ago"); }
		o += snprintf(out + o, sz - o, "%-31s %-16s %-31s %-16s %-28s %s\n", next, left, last, passed, t->name, t->unit);
	}
	snprintf(out + o, sz - o, "\n%d timers listed.\n", ntmr);
}

static int ctl_timer(const char *cmd, const char *arg, int root, char *out, size_t sz)
{
	int i = timer_index(arg);
	struct tmr *t = i >= 0 ? tmrs[i] : NULL;
	char path[PATH_MAX] = "";
	if (!t && !find_unit_file(arg, path, sizeof path)) { snprintf(out, sz, "Unit %s not found.\n", arg); return 5; }
	if (!strcmp(cmd, "is-active")) { snprintf(out, sz, "%s\n", t ? "active" : "inactive"); return t ? 0 : 3; }
	if (!strcmp(cmd, "status")) {
		int en = is_enabled(arg, NULL, 0);
		if (!t) {
			snprintf(out, sz, "* %s\n     Loaded: loaded (%s; %s)\n     Active: inactive (dead)\n", arg, path, en ? "enabled" : "disabled");
			return 3;
		}
		long bt = now_ms(CLOCK_BOOTTIME), rt = now_ms(CLOCK_REALTIME), n = timer_next_rt(t, bt, rt);
		char next[64], left[32] = "";
		fmt_when(n, next, sizeof next);
		if (n) fmt_span(n - rt, left, sizeof left);
		snprintf(out, sz, "* %s - %s\n     Loaded: loaded (%s; %s)\n     Active: active (waiting)\n    Trigger: %s%s%s%s\n   Triggers: * %s\n",
			t->name, t->desc[0] ? t->desc : t->name, t->path, en ? "enabled" : "disabled", next,
			n ? "; " : "", left, n ? " left" : "", t->unit);
		return 0;
	}
	if (!root) return 4;
	if (!strcmp(cmd, "stop") || !strcmp(cmd, "restart")) {
		if (t) timer_remove(i);
		t = NULL;
		if (!strcmp(cmd, "stop")) return 0;
	}
	if (!strcmp(cmd, "start") || !strcmp(cmd, "restart")) {
		if (t) return 0;
		if (ntmr >= MAX_TIMER || !(t = timer_load(arg))) return 1;
		t->manual = 1;
		timer_activate(t);
		tmrs[ntmr++] = t;
		return 0;
	}
	return 1;
}

static void mount_api(void)
{
	struct stat st;
	mount("proc", "/proc", "proc", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL);
	mount("sysfs", "/sys", "sysfs", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL);
	if (stat("/dev/null", &st) || !S_ISCHR(st.st_mode))
		mount("devtmpfs", "/dev", "devtmpfs", MS_NOSUID, "mode=0755");
	mkdir("/dev/pts", 0755);
	mount("devpts", "/dev/pts", "devpts", MS_NOSUID | MS_NOEXEC, "gid=5,mode=620,ptmxmode=000");
	mkdir("/dev/shm", 01777);
	mount("tmpfs", "/dev/shm", "tmpfs", MS_NOSUID | MS_NODEV, "mode=1777");
	mkdir("/dev/mqueue", 0755);
	mount("mqueue", "/dev/mqueue", "mqueue", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL);
	symlink("/proc/self/fd", "/dev/fd");
	symlink("/proc/self/fd/0", "/dev/stdin");
	symlink("/proc/self/fd/1", "/dev/stdout");
	symlink("/proc/self/fd/2", "/dev/stderr");
	struct statfs sf;
	if (statfs("/run", &sf) || sf.f_type != 0x01021994)
		mount("tmpfs", "/run", "tmpfs", MS_NOSUID | MS_NODEV, "mode=0755,size=20%");
	mkdir("/run/lock", 01777);
	mkdir("/tmp", 01777);
	mount("cgroup2", "/sys/fs/cgroup", "cgroup2", MS_NOSUID | MS_NODEV | MS_NOEXEC, "nsdelegate");
	mount("securityfs", "/sys/kernel/security", "securityfs", 0, NULL);
	mount("bpf", "/sys/fs/bpf", "bpf", 0, "mode=700");
	mount("configfs", "/sys/kernel/config", "configfs", 0, NULL);
	if (access("/sys/firmware/efi", F_OK) == 0)
		mount("efivarfs", "/sys/firmware/efi/efivars", "efivarfs", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL);
	symlink("/run", "/var/run");
	if (access("/etc/kinit/no-systemd-marker", F_OK) != 0)
		mkdir_p("/run/systemd/system", 0755);
}

static void remount_root(void)
{
	struct statfs sf;
	if (statfs("/", &sf) == 0 && (sf.f_flags & ST_RDONLY) && !cmdline_get("ro"))
		mount(NULL, "/", NULL, MS_REMOUNT, NULL);
}

static void apply_sysctl_file(const char *path)
{
	FILE *f = fopen(path, "re");
	if (!f) return;
	char line[1024];
	while (fgets(line, sizeof line, f)) {
		char *l = trim(line);
		if (!*l || *l == '#' || *l == ';') continue;
		int ignore = *l == '-';
		char *eq = strchr(l + ignore, '=');
		if (!eq) continue;
		*eq = 0;
		char *k = trim(l + ignore), *v = trim(eq + 1);
		char p[512] = "/proc/sys/";
		size_t o = strlen(p);
		for (char *c = k; *c && o < sizeof p - 1; c++) p[o++] = *c == '.' ? '/' : *c;
		p[o] = 0;
		write_file(p, v);
	}
	fclose(f);
}

static void apply_sysctls(void)
{
	static const char *dirs[] = { "/usr/lib/sysctl.d", "/etc/sysctl.d", NULL };
	for (int i = 0; dirs[i]; i++) {
		struct dirent **nl;
		int n = scandir(dirs[i], &nl, NULL, alphasort);
		for (int j = 0; j < n; j++) {
			char p[PATH_MAX];
			snprintf(p, sizeof p, "%s/%s", dirs[i], nl[j]->d_name);
			if (strstr(nl[j]->d_name, ".conf")) apply_sysctl_file(p);
			free(nl[j]);
		}
		if (n >= 0) free(nl);
	}
	apply_sysctl_file("/etc/sysctl.conf");
}

static void ensure_machine_id(void)
{
	char id[64];
	int n = read_file("/etc/machine-id", id, sizeof id);
	if (n >= 32) return;
	char uuid[64];
	if (read_file("/proc/sys/kernel/random/uuid", uuid, sizeof uuid) < 36) return;
	char out[34];
	int o = 0;
	for (int i = 0; uuid[i] && o < 32; i++)
		if (isxdigit((unsigned char)uuid[i])) out[o++] = (char)tolower((unsigned char)uuid[i]);
	out[o++] = '\n';
	out[o] = 0;
	if (write_file("/etc/machine-id", out) == 0) return;
	if (write_file("/run/machine-id", out) == 0) {
		if (access("/etc/machine-id", F_OK) != 0) {
			int fd = open("/etc/machine-id", O_WRONLY | O_CREAT | O_CLOEXEC, 0444);
			if (fd >= 0) close(fd);
		}
		mount("/run/machine-id", "/etc/machine-id", NULL, MS_BIND, NULL);
	}
}

static void set_hostname(void)
{
	char h[256];
	if (read_file("/etc/hostname", h, sizeof h) > 0) {
		char *t = trim(h);
		if (*t) sethostname(t, strlen(t));
	}
}

static void lo_up(void)
{
	int s = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	if (s < 0) return;
	struct ifreq ifr;
	memset(&ifr, 0, sizeof ifr);
	snprintf(ifr.ifr_name, IFNAMSIZ, "lo");
	if (ioctl(s, SIOCGIFFLAGS, &ifr) == 0) {
		ifr.ifr_flags |= IFF_UP | IFF_RUNNING;
		ioctl(s, SIOCSIFFLAGS, &ifr);
	}
	close(s);
}

static int have_modules(void)
{
	struct utsname u;
	if (uname(&u)) return 0;
	char p[256];
	snprintf(p, sizeof p, "/lib/modules/%s/modules.alias", u.release);
	return access(p, R_OK) == 0;
}

static void coldplug_walk(const char *dir, char **list, int *n, int max, int depth)
{
	if (depth > 12 || *n >= max) return;
	DIR *d = opendir(dir);
	if (!d) return;
	struct dirent *de;
	while ((de = readdir(d)) && *n < max) {
		if (de->d_name[0] == '.') continue;
		char p[PATH_MAX];
		snprintf(p, sizeof p, "%s/%s", dir, de->d_name);
		if (de->d_type == DT_DIR) coldplug_walk(p, list, n, max, depth + 1);
		else if (!strcmp(de->d_name, "modalias")) {
			char b[512];
			if (read_file(p, b, sizeof b) > 0) { char *t = trim(b); if (*t) list[(*n)++] = strdup(t); }
		}
	}
	closedir(d);
}

static int cmp_str(const void *a, const void *b)
{
	return strcmp(*(char *const *)a, *(char *const *)b);
}

static void coldplug(void)
{
	if (!have_modules()) return;
	static char *list[4096];
	int n = 0;
	coldplug_walk("/sys/devices", list, &n, 4000, 0);
	qsort(list, n, sizeof *list, cmp_str);
	int u = 0;
	for (int i = 0; i < n; i++) {
		if (u && !strcmp(list[u - 1], list[i])) free(list[i]);
		else list[u++] = list[i];
	}
	if (verbose) say("coldplug: %d modaliases, %d unique", n, u);
	char **argv = calloc(u + 4, sizeof *argv);
	argv[0] = "modprobe"; argv[1] = "-aq";
	for (int i = 0; i < u; i++) argv[2 + i] = list[i];
	spawn_bg(argv);
	for (int i = 0; i < u; i++) free(list[i]);
	free(argv);
	FILE *f = fopen("/etc/modules", "re");
	if (f) {
		char line[256];
		while (fgets(line, sizeof line, f)) {
			char *t = trim(line);
			if (*t && *t != '#') { char *a[] = { "modprobe", "-q", t, NULL }; spawn_bg(a); }
		}
		fclose(f);
	}
	uevfd = socket(AF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, NETLINK_KOBJECT_UEVENT);
	if (uevfd >= 0) {
		struct sockaddr_nl sa = { .nl_family = AF_NETLINK, .nl_groups = 1 };
		if (bind(uevfd, (void *)&sa, sizeof sa)) { close(uevfd); uevfd = -1; }
	}
}

static void handle_uevent(void)
{
	char buf[4096];
	ssize_t n;
	if (access("/run/udev/control", F_OK) == 0) { close(uevfd); uevfd = -1; return; }
	while ((n = recv(uevfd, buf, sizeof buf - 1, 0)) > 0) {
		buf[n] = 0;
		if (strncmp(buf, "add@", 4)) continue;
		for (char *p = buf; p < buf + n; p += strlen(p) + 1)
			if (!strncmp(p, "MODALIAS=", 9)) { char *a[] = { "modprobe", "-q", p + 9, NULL }; spawn_bg(a); }
	}
}

static char consoles[8][32];
static pid_t console_pid[8];
static int nconsoles;

static void find_consoles(void)
{
	char b[256];
	if (read_file("/sys/class/tty/console/active", b, sizeof b) <= 0) return;
	for (char *t = strtok(b, " \n"); t && nconsoles < 8; t = strtok(NULL, " \n")) {
		if (!strcmp(t, "tty0")) t = "tty1";
		char skip[256] = "", pat[40];
		snprintf(pat, sizeof pat, " %s ", t);
		if (read_file("/etc/kinit/no-getty", skip + 1, sizeof skip - 2) > 0) {
			skip[0] = ' ';
			for (char *c = skip; *c; c++) if (*c == '\n' || *c == '\t') *c = ' ';
			strcat(skip, " ");
			if (strstr(skip, pat)) continue;
		}
		snprintf(consoles[nconsoles++], 32, "%s", t);
	}
}

static void spawn_getty(int i)
{
	pid_t p = fork();
	if (p == 0) {
		child_signals();
		setsid();
		char dev[64];
		snprintf(dev, sizeof dev, "/dev/%s", consoles[i]);
		char auto_user[64] = "";
		if (read_file("/etc/kinit/autologin", auto_user, sizeof auto_user) > 0) trim(auto_user);
		char *cl = auto_user[0] ? trim(auto_user) : NULL;
		const char *ka = cmdline_get("kwick.autologin");
		if (ka) cl = (char *)(ka[0] ? ka : "root");
		if (cl && *cl) {
			setenv("KWICK_AUTOLOGIN", cl, 1);
			execl("/sbin/getty", "getty", "-n", "-l", "/usr/lib/kwick/autologin", "-L", "115200", consoles[i], "linux", (char *)NULL);
		}
		execl("/sbin/getty", "getty", "-L", "115200", consoles[i], "linux", (char *)NULL);
		_exit(127);
	}
	console_pid[i] = p;
}

static void ctl_listen(void)
{
	unlink(SOCK_PATH);
	ctlfd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
	struct sockaddr_un a = { .sun_family = AF_UNIX };
	snprintf(a.sun_path, sizeof a.sun_path, SOCK_PATH);
	if (bind(ctlfd, (void *)&a, sizeof a) || listen(ctlfd, 16)) { close(ctlfd); ctlfd = -1; return; }
	chmod(SOCK_PATH, 0666);
}

static void fmt_status(struct svc *s, char *out, size_t sz)
{
	char tgt[64] = "";
	int en = is_enabled(s->name, tgt, sizeof tgt);
	const char *sub = s->state == S_RUNNING ? "running" : s->state == S_EXITED ? "exited" :
		s->state == S_FAILED ? "failed" : s->state == S_STARTING ? "start" : "dead";
	char when[64] = "";
	if (s->since) { struct tm tm; localtime_r(&s->since, &tm); strftime(when, sizeof when, " since %a %Y-%m-%d %H:%M:%S", &tm); }
	snprintf(out, sz,
		"* %s - %s\n     Loaded: loaded (%s; %s)\n     Active: %s (%s)%s\n%s%.0d%s",
		s->name, s->desc[0] ? s->desc : s->name, s->path, en ? "enabled" : "disabled",
		state_names[s->state], sub, s->state == S_STOPPED ? "" : when,
		s->pid > 0 ? "   Main PID: " : "", s->pid, s->pid > 0 ? "\n" : "");
	if (s->state == S_FAILED) {
		size_t l = strlen(out);
		snprintf(out + l, sz - l, "     Status: exited with code %d\n", s->exit_code);
	}
}

static void do_shutdown(int how);

#define MAX_CLIENTS 32
#define ROOT_SLOTS 8
enum { C_READ = 1, C_WAIT, C_WRITE };
enum { W_START = 1, W_STOP };

struct client {
	int fd, phase, root, wait, idx;
	size_t len, olen, ooff;
	long deadline;
	char *out;
	char buf[1024];
};

static struct client clients[MAX_CLIENTS];

static void ctl_close(struct client *c)
{
	close(c->fd);
	free(c->out);
	memset(c, 0, sizeof *c);
}

static void ctl_flush(struct client *c)
{
	while (c->ooff < c->olen) {
		ssize_t n = send(c->fd, c->out + c->ooff, c->olen - c->ooff, MSG_NOSIGNAL | MSG_DONTWAIT);
		if (n > 0) { c->ooff += n; continue; }
		if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return;
		if (n < 0 && errno == EINTR) continue;
		break;
	}
	ctl_close(c);
}

static void ctl_reply(struct client *c, int rc, const char *text)
{
	size_t l = strlen(text) + 16;
	c->out = malloc(l);
	if (!c->out) { ctl_close(c); return; }
	c->olen = (size_t)snprintf(c->out, l, "%d\n%s", rc, text);
	c->ooff = 0;
	c->phase = C_WRITE;
	c->deadline = now_ms(CLOCK_MONOTONIC) + 5000;
	ctl_flush(c);
}

static int ctl_wait_done(struct client *c)
{
	struct svc *s = svcs[c->idx];
	if (c->wait == W_STOP) return s->state != S_STOPPING;
	return !s->start_after_stop && s->state != S_STOPPING && s->state != S_STARTING && !s->forking_wait;
}

static long ctl_progress(long now)
{
	long wait = LONG_MAX;
	for (int i = 0; i < MAX_CLIENTS; i++) {
		struct client *c = &clients[i];
		if (!c->phase) continue;
		if (c->phase == C_WAIT && (ctl_wait_done(c) || now >= c->deadline)) {
			ctl_reply(c, c->wait == W_START && svcs[c->idx]->state == S_FAILED ? 1 : 0, "");
			continue;
		}
		if (now >= c->deadline) { ctl_close(c); continue; }
		if (c->deadline - now < wait) wait = c->deadline - now;
	}
	return wait;
}

static void ctl_request(struct client *c)
{
	char *save, *cmd = strtok_r(c->buf, " \n", &save), *arg = strtok_r(NULL, " \n", &save);
	if (arg && (strchr(arg, '/') || arg[0] == '.')) arg = NULL;
	int root = c->root;
	static char out[65536];
	int rc = 0;
	out[0] = 0;
	size_t al = arg ? strlen(arg) : 0;
	if (!cmd) rc = 1;
	else if (!strcmp(cmd, "list")) {
		size_t o = 0;
		for (int i = 0; i < nsvc && o < sizeof out - 256; i++) {
			struct svc *s = svcs[i];
			o += snprintf(out + o, sizeof out - o, "%-40s %-8s %-10s %s\n", s->name,
				s->state == S_FAILED ? "failed" : "loaded", state_names[s->state],
				s->desc[0] ? s->desc : "");
		}
	} else if (!strcmp(cmd, "list-timers")) {
		fmt_timers(out, sizeof out);
	} else if (!strcmp(cmd, "ready")) {
		snprintf(out, sizeof out, "%ld\n", boot_ready_ms);
	} else if (!strcmp(cmd, "reload-units")) {
		if (!root) rc = 4;
		else {
			for (int i = 0; i < nsvc; i++) {
				struct svc *ns = load_unit(svcs[i]->name), *os = svcs[i];
				if (!ns) continue;
				ns->want = os->want; ns->state = os->state; ns->pid = os->pid;
				ns->since = os->since; ns->forking_wait = os->forking_wait;
				ns->restart_at = os->restart_at; ns->fails = os->fails; ns->exit_code = os->exit_code;
				ns->start_after_stop = os->start_after_stop; ns->kill_at = os->kill_at; ns->started_bt = os->started_bt;
				free_svc(os); svcs[i] = ns;
			}
			if (is_pid1) timers_scan();
		}
	} else if (!strcmp(cmd, "poweroff") || !strcmp(cmd, "reboot") || !strcmp(cmd, "halt")) {
		if (!root) rc = 4;
		else shutdown_req = cmd[0] == 'p' ? 2 : cmd[0] == 'r' ? 3 : 1;
	} else if (!arg) rc = 1;
	else if (al > 6 && !strcmp(arg + al - 6, ".timer")) rc = ctl_timer(cmd, arg, root, out, sizeof out);
	else {
		struct svc *s = svc_find(arg);
		if (!s) { snprintf(out, sizeof out, "Unit %s not found.\n", arg); rc = 5; }
		else if (!strcmp(cmd, "status") || !strcmp(cmd, "is-active")) {
			if (cmd[0] == 's') fmt_status(s, out, sizeof out);
			else snprintf(out, sizeof out, "%s\n", state_names[s->state]);
			rc = (s->state == S_RUNNING || s->state == S_EXITED) ? 0 : 3;
		} else if (!root) rc = 4;
		else if (!strcmp(cmd, "start") || !strcmp(cmd, "stop") || !strcmp(cmd, "restart")) {
			if (!strcmp(cmd, "stop")) svc_stop(s);
			else {
				if (cmd[2] == 's') { svc_stop(s); s->fails = 0; }
				svc_start(s);
			}
			for (int i = 0; i < nsvc; i++) if (svcs[i] == s) c->idx = i;
			c->wait = cmd[2] == 'o' ? W_STOP : W_START;
			c->phase = C_WAIT;
			long now = now_ms(CLOCK_MONOTONIC);
			c->deadline = now + (c->wait == W_STOP ? 7000 : 6000);
			ctl_progress(now);
			return;
		} else if (!strcmp(cmd, "reload")) {
			if (s->reload) rc = sh_run(s->reload);
			else if (s->pid > 0) kill(s->pid, SIGHUP);
		} else rc = 1;
	}
	ctl_reply(c, rc, out);
}

static void ctl_read(struct client *c)
{
	ssize_t n = recv(c->fd, c->buf + c->len, sizeof c->buf - 1 - c->len, MSG_DONTWAIT);
	if (n < 0) {
		if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) return;
		ctl_close(c);
		return;
	}
	if (n == 0 && c->len == 0) { ctl_close(c); return; }
	c->len += n;
	c->buf[c->len] = 0;
	if (n == 0 || memchr(c->buf, '\n', c->len) || c->len >= sizeof c->buf - 1) ctl_request(c);
}

static void ctl_accept(void)
{
	for (;;) {
		int fd = accept4(ctlfd, NULL, NULL, SOCK_CLOEXEC | SOCK_NONBLOCK);
		if (fd < 0) return;
		struct ucred cr;
		socklen_t cl = sizeof cr;
		int root = getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cr, &cl) == 0 && cr.uid == 0;
		int slot = -1, others = 0;
		for (int i = 0; i < MAX_CLIENTS; i++) {
			if (!clients[i].phase) { if (slot < 0) slot = i; }
			else if (!clients[i].root) others++;
		}
		if (slot < 0 || (!root && others >= MAX_CLIENTS - ROOT_SLOTS)) { close(fd); continue; }
		struct client *c = &clients[slot];
		c->fd = fd;
		c->root = root;
		c->phase = C_READ;
		c->deadline = now_ms(CLOCK_MONOTONIC) + 5000;
	}
}

static void do_shutdown(int how)
{
	say("shutting down");
	for (int i = nsvc - 1; i >= 0; i--) {
		struct svc *s = svcs[i];
		s->want = 0;
		if (s->stop && (s->state == S_RUNNING || s->state == S_EXITED)) sh_run(s->stop);
		if (s->pid > 0 && (s->state == S_RUNNING || s->state == S_STARTING)) {
			kill(-s->pid, SIGTERM); kill(s->pid, SIGTERM); kill(s->pid, SIGCONT);
			s->state = S_STOPPING;
		}
	}
	long deadline = now_ms(CLOCK_MONOTONIC) + 5000;
	for (;;) {
		int alive = 0;
		while (waitpid(-1, NULL, WNOHANG) > 0) ;
		for (int i = 0; i < nsvc; i++)
			if (svcs[i]->state == S_STOPPING && svcs[i]->pid > 0 && kill(svcs[i]->pid, 0) == 0) alive = 1;
		if (!alive || now_ms(CLOCK_MONOTONIC) > deadline) break;
		usleep(10000);
	}
	if (!is_pid1) exit(0);
	kill(-1, SIGTERM);
	kill(-1, SIGHUP);
	kill(-1, SIGCONT);
	deadline = now_ms(CLOCK_MONOTONIC) + 2000;
	for (;;) {
		pid_t p = waitpid(-1, NULL, WNOHANG);
		if (p < 0 && errno == ECHILD) break;
		if (p > 0) continue;
		if (now_ms(CLOCK_MONOTONIC) > deadline) break;
		usleep(5000);
	}
	kill(-1, SIGKILL);
	while (waitpid(-1, NULL, WNOHANG) > 0) ;
	sync();
	char *swapoff[] = { "swapoff", "-a", NULL };
	if (access("/sbin/swapoff", X_OK) == 0) run_wait(swapoff);
	FILE *f = fopen("/proc/self/mounts", "re");
	char *mps[256]; int nm = 0;
	char line[1024];
	while (f && fgets(line, sizeof line, f) && nm < 256) {
		char dev[256], mp[512], typ[64];
		if (sscanf(line, "%255s %511s %63s", dev, mp, typ) == 3 && strcmp(mp, "/")) mps[nm++] = strdup(mp);
	}
	if (f) fclose(f);
	for (int i = nm - 1; i >= 0; i--) umount2(mps[i], MNT_DETACH);
	mount(NULL, "/", NULL, MS_REMOUNT | MS_RDONLY, NULL);
	sync();
	int con = open("/dev/console", O_WRONLY | O_NOCTTY | O_CLOEXEC);
	if (con >= 0) { tcdrain(con); close(con); }
	reboot(how == 3 ? RB_AUTOBOOT : how == 2 ? RB_POWER_OFF : RB_HALT_SYSTEM);
	for (;;) pause();
}

static void main_loop(void)
{
	for (;;) {
		if (shutdown_req) do_shutdown(shutdown_req);
		long now = now_ms(CLOCK_MONOTONIC);
		int timeout = stop_tick(now);
		for (int i = 0; i < nsvc; i++) {
			struct svc *s = svcs[i];
			if (s->restart_at && s->want) {
				if (now >= s->restart_at) { s->restart_at = 0; s->state = S_STOPPED; svc_start(s); }
				else if (s->restart_at - now < timeout) timeout = (int)(s->restart_at - now);
			}
		}
		long w = timers_tick();
		if (w < timeout) timeout = (int)w;
		w = ctl_progress(now);
		if (w < timeout) timeout = (int)w;
		struct pollfd pf[3 + MAX_CLIENTS] = { { sfd, POLLIN, 0 }, { ctlfd, POLLIN, 0 }, { uevfd, POLLIN, 0 } };
		for (int i = 0; i < MAX_CLIENTS; i++) {
			struct client *c = &clients[i];
			pf[3 + i].fd = c->phase == C_READ || c->phase == C_WRITE ? c->fd : -1;
			pf[3 + i].events = c->phase == C_WRITE ? POLLOUT : POLLIN;
		}
		int r = poll(pf, 3 + MAX_CLIENTS, timeout);
		if (r <= 0) continue;
		if (pf[0].revents & POLLIN) {
			struct signalfd_siginfo si;
			while (read(sfd, &si, sizeof si) == sizeof si) {
				switch (si.ssi_signo) {
				case SIGCHLD: break;
				case SIGUSR1: shutdown_req = 1; break;
				case SIGUSR2: shutdown_req = 2; break;
				case SIGTERM: case SIGINT: shutdown_req = is_pid1 ? 3 : 2; break;
				case SIGPWR: shutdown_req = 2; break;
				}
			}
			int st;
			pid_t p;
			while ((p = waitpid(-1, &st, WNOHANG)) > 0) {
				for (int i = 0; i < nsvc; i++)
					if (svcs[i]->pid == p) { svc_exited(svcs[i], st); break; }
				for (int i = 0; i < nconsoles; i++)
					if (console_pid[i] == p && !shutdown_req) spawn_getty(i);
			}
			for (int i = 0; i < nsvc; i++) {
				struct svc *s = svcs[i];
				if (s->type == T_FORKING && s->state == S_RUNNING && s->pid > 0 && kill(s->pid, 0) < 0) {
					s->pid = 0; s->state = s->want ? S_FAILED : S_STOPPED;
				}
			}
		}
		for (int i = 0; i < MAX_CLIENTS; i++) {
			struct client *c = &clients[i];
			if (pf[3 + i].fd < 0 || !pf[3 + i].revents) continue;
			if (c->phase == C_READ) ctl_read(c);
			else if (c->phase == C_WRITE) ctl_flush(c);
		}
		if (ctlfd >= 0 && (pf[1].revents & POLLIN)) ctl_accept();
		if (uevfd >= 0 && (pf[2].revents & POLLIN)) handle_uevent();
	}
}

static void setup_signals(void)
{
	sigset_t m;
	sigemptyset(&m);
	int sigs[] = { SIGCHLD, SIGTERM, SIGINT, SIGUSR1, SIGUSR2, SIGPWR, SIGHUP };
	for (unsigned i = 0; i < sizeof sigs / sizeof *sigs; i++) sigaddset(&m, sigs[i]);
	sigprocmask(SIG_BLOCK, &m, NULL);
	sfd = signalfd(-1, &m, SFD_CLOEXEC | SFD_NONBLOCK);
	signal(SIGPIPE, SIG_IGN);
}

static void start_wanted(void)
{
	for (int i = 0; i < nsvc; i++) if (svcs[i]->want) svc_start(svcs[i]);
}

static int stage1(void)
{
	is_pid1 = 1;
	setsid();
	mount_api();
	remount_root();
	umask(022);
	setenv("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", 1);
	int con = open("/dev/console", O_RDWR | O_NOCTTY);
	if (con >= 0) { dup2(con, 0); dup2(con, 1); dup2(con, 2); if (con > 2) close(con); }
	verbose = cmdline_get("kwick.debug") != NULL;
	setup_signals();
	reboot(RB_DISABLE_CAD);
	ensure_machine_id();
	set_hostname();
	lo_up();
	apply_sysctls();
	write_file("/proc/sys/kernel/printk", "4 4 1 7");
	if (access("/etc/fstab", R_OK) == 0) { char *a[] = { "mount", "-a", NULL }; run_wait(a); }
	coldplug();
	{ char *a[] = { "systemd-tmpfiles", "--create", NULL }; cmd_tmpfiles(2, a); }
	ctl_listen();
	load_boot_units();
	start_wanted();
	timers_scan();
	boot_ready_ms = now_ms(CLOCK_BOOTTIME);
	char b[64];
	snprintf(b, sizeof b, "%ld\n", boot_ready_ms);
	write_file("/run/kinit.ready", b);
	char rel[128] = "KwickOS";
	if (read_file("/etc/kwick-release", rel, sizeof rel) > 0) trim(rel);
	say("%s ready in %ld ms (since kernel start)", rel, boot_ready_ms);
	if (!cmdline_get("kwick.noconsole")) {
		find_consoles();
		for (int i = 0; i < nconsoles; i++) spawn_getty(i);
	}
	const char *run = cmdline_get("kwick.run");
	if (run) {
		char cmd[512];
		snprintf(cmd, sizeof cmd, "%s", run);
		for (char *c = cmd; *c; c++) if (*c == '+') *c = ' ';
		pid_t p = fork();
		if (p == 0) {
			child_signals();
			execl("/bin/sh", "sh", "-c", cmd, (char *)NULL); _exit(127);
		}
	}
	main_loop();
	return 0;
}

static int supervisor(void)
{
	if (fork()) return 0;
	setsid();
	int nul = open("/dev/null", O_RDWR);
	if (nul >= 0) { dup2(nul, 0); dup2(nul, 1); dup2(nul, 2); if (nul > 2) close(nul); }
	mkdir_p("/run", 0755);
	setup_signals();
	ctl_listen();
	main_loop();
	return 0;
}

static int ctl_send(const char *cmd, const char *arg, int quiet)
{
	int c = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	struct sockaddr_un a = { .sun_family = AF_UNIX };
	snprintf(a.sun_path, sizeof a.sun_path, SOCK_PATH);
	if (connect(c, (void *)&a, sizeof a)) { close(c); return -1; }
	dprintf(c, "%s %s\n", cmd, arg ? arg : "");
	shutdown(c, SHUT_WR);
	char buf[65536];
	size_t o = 0;
	ssize_t n;
	while ((n = read(c, buf + o, sizeof buf - 1 - o)) > 0) o += n;
	close(c);
	if (!o) {
		if (!quiet) fprintf(stderr, "kinit: the service manager is busy, try again\n");
		return 1;
	}
	buf[o] = 0;
	char *nl = strchr(buf, '\n');
	int rc = atoi(buf);
	if (rc == 4 && !quiet) fprintf(stderr, "Access denied (must be root)\n");
	if (nl && !quiet) fputs(nl + 1, stdout);
	return rc;
}

static int ensure_daemon(void)
{
	if (access(SOCK_PATH, F_OK) == 0) {
		int c = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
		struct sockaddr_un a = { .sun_family = AF_UNIX };
		snprintf(a.sun_path, sizeof a.sun_path, SOCK_PATH);
		int ok = connect(c, (void *)&a, sizeof a) == 0;
		close(c);
		if (ok) return 0;
	}
	if (getuid() != 0) return -1;
	pid_t p = fork();
	if (p == 0) { execl("/proc/self/exe", "kinit", "--supervisor", (char *)NULL); execl("/sbin/kinit", "kinit", "--supervisor", (char *)NULL); _exit(1); }
	waitpid(p, NULL, 0);
	for (int i = 0; i < 100 && access(SOCK_PATH, F_OK); i++) usleep(10000);
	return access(SOCK_PATH, F_OK);
}

static void unit_name(const char *in, char *out, size_t sz)
{
	snprintf(out, sz, "%s%s", in, strchr(in, '.') ? "" : ".service");
}

static int unit_enable(const char *name, int quiet)
{
	char path[PATH_MAX];
	if (!find_unit_file(name, path, sizeof path)) { if (!quiet) fprintf(stderr, "Unit %s not found.\n", name); return 1; }
	char targets[256] = "";
	FILE *f = fopen(path, "re");
	char line[1024], sect[64] = "";
	while (f && fgets(line, sizeof line, f)) {
		char *l = trim(line);
		if (*l == '[') { snprintf(sect, sizeof sect, "%s", l); continue; }
		if (!strcmp(sect, "[Install]") && (!strncmp(l, "WantedBy=", 9) || !strncmp(l, "RequiredBy=", 11))) {
			char *v = strchr(l, '=') + 1;
			strncat(targets, " ", sizeof targets - strlen(targets) - 1);
			strncat(targets, v, sizeof targets - strlen(targets) - 1);
		}
	}
	if (f) fclose(f);
	if (!targets[0]) {
		return 0;
	}
	for (char *t = strtok(targets, " "); t; t = strtok(NULL, " ")) {
		char dir[PATH_MAX], link[PATH_MAX + 128];
		snprintf(dir, sizeof dir, "/etc/systemd/system/%s.wants", t);
		mkdir_p(dir, 0755);
		snprintf(link, sizeof link, "%s/%s", dir, name);
		unlink(link);
		if (symlink(path, link) == 0 && !quiet) printf("Created symlink %s -> %s.\n", link, path);
	}
	char st[PATH_MAX];
	snprintf(st, sizeof st, "/var/lib/kinit/disabled/%s", name);
	unlink(st);
	return 0;
}

static int unit_disable(const char *name, int quiet)
{
	DIR *d = opendir("/etc/systemd/system");
	if (!d) return 0;
	struct dirent *de;
	while ((de = readdir(d))) {
		size_t l = strlen(de->d_name);
		if (l < 7 || strcmp(de->d_name + l - 6, ".wants")) continue;
		char p[PATH_MAX];
		snprintf(p, sizeof p, "/etc/systemd/system/%s/%s", de->d_name, name);
		if (unlink(p) == 0 && !quiet) printf("Removed \"%s\".\n", p);
	}
	closedir(d);
	mkdir_p("/var/lib/kinit/disabled", 0755);
	char st[PATH_MAX];
	snprintf(st, sizeof st, "/var/lib/kinit/disabled/%s", name);
	write_file(st, "");
	return 0;
}

static int tail_log(const char *name, int lines, int follow)
{
	char p[PATH_MAX];
	snprintf(p, sizeof p, LOG_DIR "/%s.log", name);
	if (access(p, R_OK)) { snprintf(p, sizeof p, LOG_DIR "/%s.service.log", name); }
	if (access(p, R_OK)) { printf("-- No entries --\n"); return 0; }
	char n[16];
	snprintf(n, sizeof n, "%d", lines);
	fflush(stdout);
	if (follow) execlp("tail", "tail", "-n", n, "-f", p, (char *)NULL);
	char *a[] = { "tail", "-n", n, p, NULL };
	return run_wait(a);
}

static int cmd_systemctl(int argc, char **argv)
{
	int quiet = 0, now = 0;
	char *verb = NULL;
	char *units[64]; int nu = 0;
	for (int i = 1; i < argc; i++) {
		char *a = argv[i];
		if (!strcmp(a, "-q") || !strcmp(a, "--quiet")) quiet = 1;
		else if (!strcmp(a, "--now")) now = 1;
		else if (a[0] == '-') continue;
		else if (!verb) verb = a;
		else if (nu < 64) units[nu++] = a;
	}
	if (!strcmp(verb ? verb : "", "list-timers")) {
		if (ctl_send("list-timers", NULL, 0) < 0) puts("0 timers listed.");
		return 0;
	}
	if (!verb || !strcmp(verb, "list-units") || !strcmp(verb, "list-unit-files")) {
		if (ctl_send("list", NULL, 0) < 0) {
			for (int i = 0; unit_dirs[i]; i++) {
				DIR *d = opendir(unit_dirs[i]);
				struct dirent *de;
				while (d && (de = readdir(d)))
					if (strstr(de->d_name, ".service"))
						printf("%-40s %s\n", de->d_name, is_enabled(de->d_name, NULL, 0) ? "enabled" : "disabled");
				if (d) closedir(d);
			}
		}
		return 0;
	}
	if (!strcmp(verb, "daemon-reload") || !strcmp(verb, "daemon-reexec")) { ctl_send("reload-units", NULL, 1); return 0; }
	if (!strcmp(verb, "is-system-running")) { puts(access("/run/kinit.ready", F_OK) ? "offline" : "running"); return 0; }
	if (!strcmp(verb, "poweroff") || !strcmp(verb, "reboot") || !strcmp(verb, "halt"))
		return ctl_send(verb, NULL, 0) < 0 ? (kill(1, verb[0] == 'p' ? SIGUSR2 : verb[0] == 'r' ? SIGTERM : SIGUSR1) ? 1 : 0) : 0;
	int rc = 0;
	for (int i = 0; i < nu; i++) {
		char name[128];
		unit_name(units[i], name, sizeof name);
		if (!strcmp(verb, "enable")) { rc |= unit_enable(name, quiet); if (now && !ensure_daemon()) rc |= ctl_send("start", name, quiet); }
		else if (!strcmp(verb, "disable")) { rc |= unit_disable(name, quiet); if (now) ctl_send("stop", name, 1); }
		else if (!strcmp(verb, "is-enabled")) {
			char p[PATH_MAX];
			int en = is_enabled(name, NULL, 0);
			int exists = find_unit_file(name, p, sizeof p);
			if (!quiet) puts(en ? "enabled" : exists ? "disabled" : "not-found");
			rc |= en ? 0 : 1;
		} else if (!strcmp(verb, "mask")) {
			char p[PATH_MAX]; snprintf(p, sizeof p, "/etc/systemd/system/%s", name);
			unlink(p); rc |= symlink("/dev/null", p) ? 1 : 0;
		} else if (!strcmp(verb, "unmask")) {
			char p[PATH_MAX], rp[PATH_MAX]; snprintf(p, sizeof p, "/etc/systemd/system/%s", name);
			if (realpath(p, rp) && !strcmp(rp, "/dev/null")) unlink(p);
		} else if (!strcmp(verb, "cat")) {
			char p[PATH_MAX];
			if (find_unit_file(name, p, sizeof p)) { printf("# %s\n", p); fflush(stdout); char *a[] = { "cat", p, NULL }; run_wait(a); }
			else rc = 1;
		} else if (!strcmp(verb, "status")) {
			int r = ctl_send("status", name, quiet);
			if (r < 0) { if (!quiet) printf("* %s\n     Active: inactive (no service manager running)\n", name); r = 3; }
			if (!quiet) { printf("\n"); tail_log(name, 10, 0); }
			rc |= r;
		} else if (!strcmp(verb, "is-active") || !strcmp(verb, "is-failed")) {
			int r = ctl_send("is-active", name, quiet);
			if (r < 0) { if (!quiet) puts("inactive"); r = 3; }
			rc |= r;
		} else if (!strcmp(verb, "start") || !strcmp(verb, "stop") || !strcmp(verb, "restart") ||
			   !strcmp(verb, "reload") || !strcmp(verb, "try-restart") || !strcmp(verb, "reload-or-restart") ||
			   !strcmp(verb, "condrestart") || !strcmp(verb, "force-reload")) {
			const char *v = !strcmp(verb, "reload") ? "reload" : !strcmp(verb, "stop") ? "stop" :
				!strcmp(verb, "start") ? "start" : "restart";
			if (!strcmp(v, "stop") && access(SOCK_PATH, F_OK)) continue;
			if (ensure_daemon()) { fprintf(stderr, "kinit: cannot reach service manager\n"); return 1; }
			int r = ctl_send(v, name, quiet);
			if (r && !quiet && strcmp(v, "stop"))
				fprintf(stderr, "Job for %s failed. See \"journalctl -u %s\" for details.\n", name, name);
			rc |= r;
		} else { fprintf(stderr, "systemctl: unsupported verb '%s'\n", verb); return 1; }
	}
	return rc;
}

static int cmd_journalctl(int argc, char **argv)
{
	const char *unit = NULL;
	int lines = 50, follow = 0;
	for (int i = 1; i < argc; i++) {
		if ((!strcmp(argv[i], "-u") || !strcmp(argv[i], "--unit")) && i + 1 < argc) unit = argv[++i];
		else if (!strncmp(argv[i], "--unit=", 7)) unit = argv[i] + 7;
		else if (!strcmp(argv[i], "-n") && i + 1 < argc) lines = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-f") || !strcmp(argv[i], "--follow")) follow = 1;
		else if (!strcmp(argv[i], "-k") || !strcmp(argv[i], "--dmesg")) { execlp("dmesg", "dmesg", (char *)NULL); }
	}
	if (unit) { char n[128]; unit_name(unit, n, sizeof n); return tail_log(n, lines, follow); }
	if (follow) execlp("logread", "logread", "-f", (char *)NULL);
	execlp("logread", "logread", (char *)NULL);
	execlp("dmesg", "dmesg", (char *)NULL);
	return 1;
}

static int cmd_deb_helper(int argc, char **argv)
{
	int quiet = 0, i = 1;
	for (; i < argc && argv[i][0] == '-'; i++) if (!strcmp(argv[i], "--quiet")) quiet = 1;
	if (i >= argc) return 1;
	const char *verb = argv[i++];
	int rc = 0;
	for (; i < argc; i++) {
		char name[128];
		unit_name(argv[i], name, sizeof name);
		if (!strcmp(verb, "enable")) rc |= unit_enable(name, 1);
		else if (!strcmp(verb, "disable") || !strcmp(verb, "purge")) unit_disable(name, 1);
		else if (!strcmp(verb, "was-enabled")) {
			char st[PATH_MAX];
			snprintf(st, sizeof st, "/var/lib/kinit/disabled/%s", name);
			rc |= access(st, F_OK) == 0 ? 1 : 0;
		} else if (!strcmp(verb, "is-enabled")) rc |= is_enabled(name, NULL, 0) ? 0 : 1;
		else if (!strcmp(verb, "debian-installed")) rc |= is_enabled(name, NULL, 0) ? 0 : 1;
		else if (!strcmp(verb, "mask")) {
			char p[PATH_MAX]; snprintf(p, sizeof p, "/etc/systemd/system/%s", name);
			if (access(p, F_OK)) symlink("/dev/null", p);
		} else if (!strcmp(verb, "unmask")) {
			char p[PATH_MAX], rp[PATH_MAX]; snprintf(p, sizeof p, "/etc/systemd/system/%s", name);
			if (realpath(p, rp) && !strcmp(rp, "/dev/null")) unlink(p);
		}
	}
	(void)quiet;
	return rc;
}

static int policy_denies(void)
{
	if (access("/usr/sbin/policy-rc.d", X_OK) == 0) {
		char *a[] = { "/usr/sbin/policy-rc.d", NULL };
		return run_wait(a) == 101;
	}
	return 0;
}

static int cmd_deb_invoke(int argc, char **argv)
{
	if (argc < 3 || policy_denies()) return 0;
	if (access(SOCK_PATH, F_OK)) return 0;
	int rc = 0;
	for (int i = 2; i < argc; i++) {
		char name[128];
		unit_name(argv[i], name, sizeof name);
		const char *v = !strcmp(argv[1], "stop") ? "stop" : !strcmp(argv[1], "start") ? "start" :
			!strcmp(argv[1], "reload") ? "reload" : "restart";
		rc |= ctl_send(v, name, 1) > 0;
	}
	return rc;
}

static int cmd_invoke_rcd(int argc, char **argv)
{
	int skip_native = 0, i = 1;
	for (; i < argc && argv[i][0] == '-'; i++) if (!strcmp(argv[i], "--skip-systemd-native")) skip_native = 1;
	if (argc - i < 2) return 1;
	const char *svc = argv[i], *action = argv[i + 1];
	char name[128], p[PATH_MAX];
	unit_name(svc, name, sizeof name);
	int has_unit = find_unit_file(name, p, sizeof p);
	if (has_unit && skip_native && access("/run/systemd/system", F_OK) == 0) return 0;
	char rp[PATH_MAX];
	if (has_unit && realpath(p, rp) && !strcmp(rp, "/dev/null")) return 0;
	if (policy_denies()) return 0;
	if (access(SOCK_PATH, F_OK)) return 0;
	if (has_unit) {
		char *a[] = { "systemctl", (char *)action, name, NULL };
		return cmd_systemctl(3, a);
	}
	snprintf(p, sizeof p, "/etc/init.d/%s", svc);
	if (access(p, X_OK)) return 0;
	execl(p, p, action, (char *)NULL);
	return 1;
}

static int cmd_service(int argc, char **argv)
{
	if (argc >= 2 && !strcmp(argv[1], "--status-all")) { char *a[] = { "systemctl", "list-units", NULL }; return cmd_systemctl(2, a); }
	if (argc < 3) { fprintf(stderr, "Usage: service <name> <start|stop|restart|reload|status>\n"); return 1; }
	char name[128], p[PATH_MAX];
	unit_name(argv[1], name, sizeof name);
	if (find_unit_file(name, p, sizeof p)) {
		char *a[] = { "systemctl", argv[2], name, NULL };
		return cmd_systemctl(3, a);
	}
	snprintf(p, sizeof p, "/etc/init.d/%s", argv[1]);
	execv(p, argv + 1);
	fprintf(stderr, "%s: unrecognized service\n", argv[1]);
	return 1;
}

static int cmd_power(const char *how, int argc, char **argv)
{
	int force = 0;
	for (int i = 1; i < argc; i++) if (!strcmp(argv[i], "-f") || !strcmp(argv[i], "--force")) force = 1;
	if (force) { sync(); reboot(how[0] == 'p' ? RB_POWER_OFF : how[0] == 'r' ? RB_AUTOBOOT : RB_HALT_SYSTEM); }
	if (ctl_send(how, NULL, 0) >= 0) return 0;
	return kill(1, how[0] == 'p' ? SIGUSR2 : how[0] == 'r' ? SIGTERM : SIGUSR1) ? 1 : 0;
}

#include "syscompat.c"
#include "growroot.c"

int main(int argc, char **argv)
{
	const char *self = strrchr(argv[0], '/');
	self = self ? self + 1 : argv[0];
	if (!strcmp(self, "systemctl")) return cmd_systemctl(argc, argv);
	if (!strcmp(self, "journalctl")) return cmd_journalctl(argc, argv);
	if (!strcmp(self, "service")) return cmd_service(argc, argv);
	if (!strcmp(self, "deb-systemd-helper")) return cmd_deb_helper(argc, argv);
	if (!strcmp(self, "deb-systemd-invoke")) return cmd_deb_invoke(argc, argv);
	if (!strcmp(self, "invoke-rc.d")) return cmd_invoke_rcd(argc, argv);
	if (!strcmp(self, "update-rc.d")) return 0;
	if (!strcmp(self, "systemd-sysusers")) return cmd_sysusers(argc, argv);
	if (!strcmp(self, "systemd-tmpfiles")) return cmd_tmpfiles(argc, argv);
	if (!strcmp(self, "kwick-growroot")) return cmd_growroot(argc, argv);
	if (!strcmp(self, "poweroff") || !strcmp(self, "reboot") || !strcmp(self, "halt")) return cmd_power(self, argc, argv);
	if (argc > 1 && !strcmp(argv[1], "--version")) { puts("kinit " KINIT_VERSION); return 0; }
	if (argc > 1 && !strcmp(argv[1], "--supervisor")) return supervisor();
	if (getpid() != 1) {
		fprintf(stderr, "kinit %s: must run as PID 1 (or use --supervisor, or call as systemctl/service/journalctl)\n", KINIT_VERSION);
		return 1;
	}
	if (access("/etc/kwick-release", F_OK) != 0) { is_pid1 = 1; stage0(); }
	return stage1();
}
