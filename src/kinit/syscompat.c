/*
 * systemd-sysusers and systemd-tmpfiles compatible applets for kinit.
 * Debian trixie packages declare "Depends: systemd | systemd-sysusers"
 * and call these from maintainer scripts; implementing the common subset
 * here avoids pulling all of systemd into a KwickOS system.
 * Included from kinit.c (shares its static helpers).
 */

static int split_tokens(char *s, char **tok, int max)
{
	int n = 0;
	while (*s && n < max) {
		while (isspace((unsigned char)*s)) s++;
		if (!*s) break;
		if (*s == '"' || *s == '\'') {
			char q = *s++;
			tok[n++] = s;
			while (*s && *s != q) s++;
		} else {
			tok[n++] = s;
			while (*s && !isspace((unsigned char)*s)) s++;
		}
		if (*s) *s++ = 0;
	}
	return n;
}

static int id_in_file(const char *file, int field, long id, const char *name)
{
	FILE *f = fopen(file, "re");
	if (!f) return 0;
	char line[1024];
	int found = 0;
	while (!found && fgets(line, sizeof line, f)) {
		char *p = line, *flds[8] = { 0 };
		int n = 0;
		flds[n++] = p;
		for (; *p && n < 8; p++) if (*p == ':') { *p = 0; flds[n++] = p + 1; }
		if (name && !strcmp(flds[0], name)) found = 1;
		if (id >= 0 && n > field && flds[field] && atol(flds[field]) == id) found = 1;
	}
	fclose(f);
	return found;
}

static long free_sys_id(void)
{
	for (long id = 999; id >= 100; id--)
		if (!id_in_file("/etc/passwd", 2, id, NULL) && !id_in_file("/etc/group", 2, id, NULL)) return id;
	return -1;
}

static void append_line(const char *file, const char *line, mode_t mode)
{
	int fd = open(file, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, mode);
	if (fd < 0) return;
	(void)!write(fd, line, strlen(line));
	close(fd);
}

static long group_gid(const char *name)
{
	FILE *f = fopen("/etc/group", "re");
	if (!f) return -1;
	char line[1024];
	long gid = -1;
	size_t nl = strlen(name);
	while (fgets(line, sizeof line, f))
		if (!strncmp(line, name, nl) && line[nl] == ':') {
			char *p = strchr(line + nl + 1, ':');
			if (p) gid = atol(p + 1);
			break;
		}
	fclose(f);
	return gid;
}

static void add_group_member(const char *group, const char *user)
{
	FILE *f = fopen("/etc/group", "re");
	if (!f) return;
	char out[65536] = "", line[2048];
	size_t gl = strlen(group);
	while (fgets(line, sizeof line, f)) {
		if (!strncmp(line, group, gl) && line[gl] == ':') {
			char *nl = strchr(line, '\n'); if (nl) *nl = 0;
			char *last = strrchr(line, ':');
			int has = 0;
			if (last) {
				char tmp[1024]; snprintf(tmp, sizeof tmp, "%s", last + 1);
				for (char *t = strtok(tmp, ","); t; t = strtok(NULL, ",")) if (!strcmp(t, user)) has = 1;
			}
			if (!has) { strncat(line, last && last[1] ? "," : "", sizeof line - strlen(line) - 1); strncat(line, user, sizeof line - strlen(line) - 1); }
			strncat(line, "\n", sizeof line - strlen(line) - 1);
		}
		strncat(out, line, sizeof out - strlen(out) - 1);
	}
	fclose(f);
	char tmpf[] = "/etc/group.kinit-tmp";
	if (write_file(tmpf, out) == 0) { chmod(tmpf, 0644); rename(tmpf, "/etc/group"); }
}

static void sysusers_line(char *line)
{
	char *t[8];
	int n = split_tokens(line, t, 8);
	if (n < 2 || t[0][0] == '#') return;
	char type = t[0][0];
	const char *name = t[1];
	const char *idspec = n > 2 ? t[2] : "-";
	char buf[1024];
	if (type == 'g') {
		if (group_gid(name) >= 0) return;
		long gid = (idspec[0] != '-' && isdigit((unsigned char)idspec[0])) ? atol(idspec) : free_sys_id();
		if (gid < 0 || id_in_file("/etc/group", 2, gid, NULL)) gid = free_sys_id();
		snprintf(buf, sizeof buf, "%s:x:%ld:\n", name, gid);
		append_line("/etc/group", buf, 0644);
		if (access("/etc/gshadow", F_OK) == 0) { snprintf(buf, sizeof buf, "%s:!::\n", name); append_line("/etc/gshadow", buf, 0640); }
	} else if (type == 'u') {
		if (id_in_file("/etc/passwd", 0, -1, name)) return;
		long uid = -1, gid = -1;
		if (idspec[0] != '-') {
			if (idspec[0] == '/') { struct stat st; if (stat(idspec, &st) == 0) { uid = st.st_uid; gid = st.st_gid; } }
			else {
				uid = atol(idspec);
				const char *c = strchr(idspec, ':');
				if (c) gid = isdigit((unsigned char)c[1]) ? atol(c + 1) : group_gid(c + 1);
			}
		}
		if (uid < 0 || id_in_file("/etc/passwd", 2, uid, NULL)) uid = free_sys_id();
		if (gid < 0) {
			gid = group_gid(name);
			if (gid < 0) {
				gid = id_in_file("/etc/group", 2, uid, NULL) ? free_sys_id() : uid;
				snprintf(buf, sizeof buf, "%s:x:%ld:\n", name, gid);
				append_line("/etc/group", buf, 0644);
				if (access("/etc/gshadow", F_OK) == 0) { snprintf(buf, sizeof buf, "%s:!::\n", name); append_line("/etc/gshadow", buf, 0640); }
			}
		}
		const char *gecos = n > 3 && strcmp(t[3], "-") ? t[3] : "";
		const char *home = n > 4 && strcmp(t[4], "-") ? t[4] : "/";
		const char *shell = n > 5 && strcmp(t[5], "-") ? t[5] : "/usr/sbin/nologin";
		snprintf(buf, sizeof buf, "%s:x:%ld:%ld:%s:%s:%s\n", name, uid, gid, gecos, home, shell);
		append_line("/etc/passwd", buf, 0644);
		snprintf(buf, sizeof buf, "%s:!*:%ld::::::\n", name, (long)(time(NULL) / 86400));
		append_line("/etc/shadow", buf, 0640);
	} else if (type == 'm' && n >= 3) {
		if (group_gid(t[2]) < 0) {
			long gid = free_sys_id();
			snprintf(buf, sizeof buf, "%s:x:%ld:\n", t[2], gid);
			append_line("/etc/group", buf, 0644);
		}
		add_group_member(t[2], name);
	}
}

static const char *sysusers_dirs[] = { "/etc/sysusers.d", "/run/sysusers.d", "/usr/lib/sysusers.d", NULL };
static const char *tmpfiles_dirs[] = { "/etc/tmpfiles.d", "/run/tmpfiles.d", "/usr/lib/tmpfiles.d", NULL };

/* Process one config file, or (name == NULL) every file of the dirs. */
static void conf_each(const char **dirs, const char *name, void (*fn)(char *))
{
	if (name && name[0] == '/') {
		FILE *f = fopen(name, "re");
		char line[2048];
		while (f && fgets(line, sizeof line, f)) fn(line);
		if (f) fclose(f);
		return;
	}
	if (name) {
		for (int i = 0; dirs[i]; i++) {
			char p[PATH_MAX];
			snprintf(p, sizeof p, "%s/%s", dirs[i], name);
			if (access(p, R_OK) == 0) { conf_each(dirs, p, fn); return; }
		}
		return;
	}
	/* all files; earlier dirs override later ones with the same name */
	char seen[256][128];
	int nseen = 0;
	for (int i = 0; dirs[i]; i++) {
		struct dirent **nl;
		int n = scandir(dirs[i], &nl, NULL, alphasort);
		for (int j = 0; j < n; j++) {
			const char *d = nl[j]->d_name;
			size_t l = strlen(d);
			int dup = 0;
			for (int k = 0; k < nseen; k++) if (!strcmp(seen[k], d)) dup = 1;
			if (!dup && l > 5 && !strcmp(d + l - 5, ".conf")) {
				if (nseen < 256) snprintf(seen[nseen++], 128, "%s", d);
				char p[PATH_MAX];
				snprintf(p, sizeof p, "%s/%s", dirs[i], d);
				conf_each(dirs, p, fn);
			}
			free(nl[j]);
		}
		if (n >= 0) free(nl);
	}
}

static int cmd_sysusers(int argc, char **argv)
{
	int any = 0;
	for (int i = 1; i < argc; i++) {
		if (argv[i][0] == '-') { if (!strcmp(argv[i], "--root") && i + 1 < argc) i++; continue; }
		conf_each(sysusers_dirs, argv[i], sysusers_line);
		any = 1;
	}
	if (!any) conf_each(sysusers_dirs, NULL, sysusers_line);
	return 0;
}

static void owner_of(const char *u, const char *g, uid_t *uid, gid_t *gid)
{
	*uid = (uid_t)-1; *gid = (gid_t)-1;
	if (u && strcmp(u, "-")) { struct passwd *pw = getpwnam(u); if (pw) *uid = pw->pw_uid; else if (isdigit((unsigned char)u[0])) *uid = atoi(u); }
	if (g && strcmp(g, "-")) { struct group *gr = getgrnam(g); if (gr) *gid = gr->gr_gid; else if (isdigit((unsigned char)g[0])) *gid = atoi(g); }
}

static void tmpfiles_line(char *line)
{
	char *t[7];
	int n = split_tokens(line, t, 7);
	if (n < 2 || t[0][0] == '#') return;
	char type = t[0][0];
	int plus = strchr(t[0], '+') != NULL;
	char *path = expand_spec(t[1], "");
	const char *mode_s = n > 2 ? t[2] : "-";
	uid_t uid; gid_t gid;
	owner_of(n > 3 ? t[3] : NULL, n > 4 ? t[4] : NULL, &uid, &gid);
	const char *arg = n > 6 ? t[6] : NULL;
	mode_t mode = 0;
	int have_mode = mode_s[0] != '-';
	if (have_mode) mode = (mode_t)strtol(mode_s + (mode_s[0] == '~'), NULL, 8);
	switch (type) {
	case 'd': case 'D': case 'v': case 'q': case 'Q':
		mkdir_p(path, have_mode ? mode : 0755);
		if (have_mode) chmod(path, mode);
		if (uid != (uid_t)-1 || gid != (gid_t)-1) (void)!chown(path, uid, gid);
		break;
	case 'f': case 'F': {
		int exists = access(path, F_OK) == 0;
		if (!exists || type == 'F' || plus) {
			int fd = open(path, O_WRONLY | O_CREAT | O_CLOEXEC | ((type == 'F' || plus) ? O_TRUNC : 0), have_mode ? mode : 0644);
			if (fd >= 0) { if (arg && (!exists || type == 'F' || plus)) (void)!write(fd, arg, strlen(arg)); close(fd); }
		}
		if (have_mode) chmod(path, mode);
		if (uid != (uid_t)-1 || gid != (gid_t)-1) (void)!chown(path, uid, gid);
		break;
	}
	case 'w':
		if (arg && access(path, W_OK) == 0) { int fd = open(path, O_WRONLY | O_CLOEXEC | (plus ? O_APPEND : 0)); if (fd >= 0) { (void)!write(fd, arg, strlen(arg)); close(fd); } }
		break;
	case 'L':
		if (plus) unlink(path);
		if (arg) { char dir[PATH_MAX]; snprintf(dir, sizeof dir, "%s", path); char *s = strrchr(dir, '/'); if (s && s != dir) { *s = 0; mkdir_p(dir, 0755); } (void)!symlink(arg, path); }
		break;
	case 'z': case 'Z':
		if (have_mode) chmod(path, mode);
		if (uid != (uid_t)-1 || gid != (gid_t)-1) (void)!chown(path, uid, gid);
		break;
	case 'r':
		unlink(path); rmdir(path);
		break;
	default: /* x X e R C a A h p c b: not needed for a working system */
		break;
	}
	free(path);
}

static int cmd_tmpfiles(int argc, char **argv)
{
	int create = 0, any = 0;
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--create") || !strcmp(argv[i], "--boot")) create = 1;
		else if (!strcmp(argv[i], "--root") && i + 1 < argc) i++;
		else if (argv[i][0] != '-') { if (create) conf_each(tmpfiles_dirs, argv[i], tmpfiles_line); any = 1; }
	}
	if (create && !any) conf_each(tmpfiles_dirs, NULL, tmpfiles_line);
	return 0;
}
