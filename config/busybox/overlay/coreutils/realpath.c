/* vi: set sw=4 ts=4: */
/*
 * realpath implementation for busybox, with GNU coreutils options
 * (-e -m -s -q -z) used by Debian maintainer scripts. KwickOS overlay.
 *
 * Licensed under GPLv2, see file LICENSE in this source tree.
 */
//config:config REALPATH
//config:	bool "realpath (3 kb)"
//config:	default y
//config:	help
//config:	Return the canonicalized absolute pathname.

//applet:IF_REALPATH(APPLET(realpath, BB_DIR_USR_BIN, BB_SUID_DROP))

//kbuild:lib-$(CONFIG_REALPATH) += realpath.o

//usage:#define realpath_trivial_usage
//usage:       "[-emsqz] FILE..."
//usage:#define realpath_full_usage "\n\n"
//usage:       "Print absolute pathnames of FILEs\n"
//usage:     "\n	-e	All components must exist"
//usage:     "\n	-m	No component needs to exist"
//usage:     "\n	-s	Don't expand symlinks"
//usage:     "\n	-q	Suppress error messages"
//usage:     "\n	-z	End each output line with NUL"

#include "libbb.h"

/* Make absolute and collapse ".", ".." and "//" without touching the fs. */
static char *lexical(const char *p)
{
	char *buf, *out, *o, *s;
	if (p[0] != '/') {
		char *cwd = xrealloc_getcwd_or_warn(NULL);
		buf = concat_path_file(cwd ? cwd : "/", p);
		free(cwd);
	} else {
		buf = xstrdup(p);
	}
	out = xzalloc(strlen(buf) + 2);
	o = out;
	s = buf;
	while (*s) {
		char *e;
		size_t l;
		while (*s == '/')
			s++;
		if (!*s)
			break;
		e = strchrnul(s, '/');
		l = e - s;
		if (l == 1 && s[0] == '.') {
			/* skip */
		} else if (l == 2 && s[0] == '.' && s[1] == '.') {
			char *sl = strrchr(out, '/');
			if (sl)
				*sl = '\0';
			o = out + strlen(out);
		} else {
			*o++ = '/';
			memcpy(o, s, l);
			o += l;
			*o = '\0';
		}
		s = e;
	}
	if (!out[0])
		strcpy(out, "/");
	free(buf);
	return out;
}

/* Resolve the longest existing prefix, append the rest lexically. */
static char *canon_missing(const char *p)
{
	char *abs = lexical(p);
	char *cut = abs + strlen(abs);
	for (;;) {
		char save = *cut;
		char *r;
		*cut = '\0';
		r = abs[0] ? xmalloc_realpath(abs) : xstrdup("/");
		*cut = save;
		if (r) {
			const char *rest = cut;
			char *res;
			while (*rest == '/')
				rest++;
			res = *rest ? concat_path_file(r, rest) : xstrdup(r);
			free(r);
			free(abs);
			return res;
		}
		while (cut > abs && *--cut != '/')
			continue;
	}
}

int realpath_main(int argc, char **argv) MAIN_EXTERNALLY_VISIBLE;
int realpath_main(int argc UNUSED_PARAM, char **argv)
{
	int retval = EXIT_SUCCESS;
	unsigned opt = getopt32long(argv, "emsqzLP",
		"canonicalize-existing\0" No_argument "e"
		"canonicalize-missing\0"  No_argument "m"
		"strip\0"                 No_argument "s"
		"no-symlinks\0"           No_argument "s"
		"quiet\0"                 No_argument "q"
		"zero\0"                  No_argument "z"
		"logical\0"               No_argument "L"
		"physical\0"              No_argument "P"
	);
	argv += optind;
	if (!*argv)
		bb_show_usage();
	do {
		char *r;
		if (opt & 4)
			r = lexical(*argv);
		else if (opt & 2)
			r = canon_missing(*argv);
		else if (opt & 1)
			r = xmalloc_realpath(*argv);
		else
			r = xmalloc_realpath_coreutils(*argv);
		if (r) {
			fputs(r, stdout);
			putchar((opt & 16) ? '\0' : '\n');
			free(r);
		} else {
			retval = EXIT_FAILURE;
			if (!(opt & 8))
				bb_simple_perror_msg(*argv);
		}
	} while (*++argv);
	fflush_stdout_and_exit(retval);
}
