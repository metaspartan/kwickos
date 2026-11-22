#!/bin/sh
T=/usr/sbin/kwick-snapshot
js() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n\r\t' '   '; }

case ${1:-} in
files)
	dir=$2
	live=$3
	echo "[files]"
	[ -d "$dir" ] || exit 0
	ls -A "$dir" 2>/dev/null | head -n 3000 | while IFS= read -r n; do
		p=$dir/$n
		if [ -L "$p" ]; then t=l; elif [ -d "$p" ]; then t=d; else t=f; fi
		set -- $(stat -c '%s %Y' "$p" 2>/dev/null)
		sz=${1:-0}
		mt=${2:-0}
		lp=$live/$n
		if [ ! -e "$lp" ] && [ ! -L "$lp" ]; then
			s=gone
		elif [ "$t" = d ]; then
			s=same
		else
			set -- $(stat -c '%s %Y' "$lp" 2>/dev/null)
			if [ "${1:-}" = "$sz" ] && [ "${2:-}" = "$mt" ]; then s=same; else s=changed; fi
		fi
		r=0
		[ -r "$p" ] && r=1
		printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$t" "$sz" "$mt" "$s" "$r" "$n"
	done | sort -t'	' -k1,1 -k6,6f
	;;
pkgs)
	echo "[pkgs]"
	"$T" packages "$2" "${3:-current}" --json 2>/dev/null
	;;
changes)
	echo "[changes]"
	"$T" diff -c "$2" "$3" "$4" --json 2>/dev/null
	;;
request)
	f=${XDG_RUNTIME_DIR:-/tmp}/kwick-snapshots.request
	echo "[request]"
	[ -f "$f" ] && cat "$f" && rm -f "$f"
	;;
restore)
	src=$2
	dst=$3
	mode=$4
	parent=$(dirname "$dst")
	[ -d "$parent" ] || mkdir -p "$parent" || exit 1
	if [ -e "$dst" ] || [ -L "$dst" ]; then
		if [ "$mode" = both ]; then
			stamp=$(date '+%Y-%m-%d %H.%M.%S')
			base=${dst##*/}
			case $base in
			?*.*) dst="$parent/${base%.*} (restored $stamp).${base##*.}" ;;
			*) dst="$parent/$base (restored $stamp)" ;;
			esac
		elif gio trash "$dst" 2>/dev/null || kioclient6 move "$dst" trash:/ >/dev/null 2>&1 || kioclient move "$dst" trash:/ >/dev/null 2>&1; then
			:
		else
			mv "$dst" "$dst.before-restore" || exit 1
		fi
	fi
	cp -a "$src" "$dst" || exit 1
	echo "$dst"
	;;
*)
	echo "[status]"
	[ -x "$T" ] && "$T" status --json 2>/dev/null
	echo "[list]"
	[ -x "$T" ] && "$T" list --json 2>/dev/null
	echo "[access]"
	if sudo -n true 2>/dev/null; then echo sudo; elif id -nG | grep -qwE 'sudo|wheel'; then echo group; else echo none; fi
	echo "[user]"
	id -un
	echo "[home]"
	printf '%s\n' "$HOME"
	;;
esac
