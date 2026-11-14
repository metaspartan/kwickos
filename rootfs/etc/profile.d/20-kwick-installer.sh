case $- in *i*) ;; *) return 2>/dev/null || exit 0 ;; esac
[ -e /run/media/kwick/root.erofs ] || return 0 2>/dev/null || exit 0
[ -n "${KWICK_INSTALLER_HINT:-}" ] && return 0 2>/dev/null
export KWICK_INSTALLER_HINT=1
if [ -z "${SSH_CONNECTION:-}" ] && [ ! -e /run/kwick-installer.auto ] && grep -q 'kwick\.install' /proc/cmdline 2>/dev/null; then
	: >/run/kwick-installer.auto
	exec /usr/bin/kwick-installer
fi
printf '  \033[1;36mRun kwick-installer to install KwickOS\033[0m\n\n'
