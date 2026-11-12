#!/bin/sh
# KwickOS changes to BusyBox, applied to a pristine source tree ($1).
# Goal: GNU coreutils behaviour where Debian maintainer scripts rely on it.
# (Anything not covered here is handled at runtime by kpkg's self-healing
# fallback, which installs the real GNU tool on demand.)
set -eu
T=${1:?busybox source dir}
HERE=$(cd "$(dirname "$0")" && pwd)

# 1. Full-file overlays (realpath with -e/-m/-s/-q/-z).
cp -r "$HERE/overlay/." "$T/"
find "$T" -path "$T/coreutils/realpath.c" -exec sed -i 's/\r$//' {} +

# 2. date -d: accept what GNU `date` prints, RFC 2822 and ISO 8601.
grep -q 'KwickOS: GNU date formats' "$T/libbb/time.c" || perl -0pi -e '
s{(\t\t"%b %d %T %Y" "\\0"[^\n]*\n)}{$1\t\t/* KwickOS: GNU date formats */\n\t\t"%a %b %d %T UTC %Y" "\\0"\n\t\t"%a %b %d %T GMT %Y" "\\0"\n\t\t"%a %b %d %T %Y" "\\0"\n\t\t"%a, %d %b %Y %T %z" "\\0"\n\t\t"%Y-%m-%dT%T%z" "\\0"\n\t\t"%Y-%m-%dT%T" "\\0"\n\t\t"%d %b %Y" "\\0"\n}' "$T/libbb/time.c"
grep -q 'KwickOS: GNU date formats' "$T/libbb/time.c"

# 3. grep: GNU long options (--quiet, --invert-match, ...).
perl -0pi -e '
s{"color\\0" Optional_argument "\\xff",}{"color\\0" Optional_argument "\\xff"
\t\t"quiet\\0" No_argument "q" "silent\\0" No_argument "q" "invert-match\\0" No_argument "v"
\t\t"ignore-case\\0" No_argument "i" "count\\0" No_argument "c" "line-number\\0" No_argument "n"
\t\t"files-with-matches\\0" No_argument "l" "files-without-match\\0" No_argument "L"
\t\t"no-messages\\0" No_argument "s" "fixed-strings\\0" No_argument "F" "extended-regexp\\0" No_argument "E"
\t\t"word-regexp\\0" No_argument "w" "line-regexp\\0" No_argument "x" "only-matching\\0" No_argument "o"
\t\t"recursive\\0" No_argument "r" "dereference-recursive\\0" No_argument "R"
\t\t"with-filename\\0" No_argument "H" "no-filename\\0" No_argument "h" "text\\0" No_argument "a"
\t\t"regexp\\0" Required_argument "e" "file\\0" Required_argument "f" "max-count\\0" Required_argument "m"
\t\t"after-context\\0" Required_argument "A" "before-context\\0" Required_argument "B" "context\\0" Required_argument "C",}' "$T/findutils/grep.c"
grep -q '"invert-match' "$T/findutils/grep.c"

# 4. logger: --tag --priority --stderr --id (used by Debian adduser).
perl -0pi -e 's{opt = getopt32\(argv, "p:st:", &str_p, &str_t\);}{opt = getopt32long(argv, "p:st:i", "priority\\0" Required_argument "p" "stderr\\0" No_argument "s" "tag\\0" Required_argument "t" "id\\0" No_argument "i", &str_p, &str_t);}' "$T/sysklogd/logger.c"
grep -q '"priority' "$T/sysklogd/logger.c"

# 5. readlink: -e and -m (canonicalize existing / missing).
perl -0pi -e 's~IF_FEATURE_READLINK_FOLLOW\("fvsq"\)~IF_FEATURE_READLINK_FOLLOW("fvsqem")~; s~if \(opt & 2\) \{ /\* -f \*/\n\t\tbuf = xmalloc_realpath_coreutils\(argv\[optind\]\);~if (opt & (2|32|64)) { /* -f -e -m */\n\t\tbuf = xmalloc_realpath_coreutils(argv[optind]);\n\t\tif (!buf && (opt & 64)) { /* -m: missing components are fine */\n\t\t\tchar *cwd = argv[optind][0] == 0x2f ? NULL : xrealloc_getcwd_or_warn(NULL);\n\t\t\tbuf = cwd ? concat_path_file(cwd, argv[optind]) : xstrdup(argv[optind]);\n\t\t\tfree(cwd);\n\t\t}~' "$T/coreutils/readlink.c"
grep -q 'fvsqem' "$T/coreutils/readlink.c"
grep -q 'missing components are fine' "$T/coreutils/readlink.c"
echo "busybox: KwickOS patches applied"
