#!/bin/sh
if [ -z "${KWICK_INSTALL_INHIBITED:-}" ]; then
  export KWICK_INSTALL_INHIBITED=1
  case ${XDG_CURRENT_DESKTOP:-} in
    *KDE*) command -v kde-inhibit >/dev/null 2>&1 && exec kde-inhibit --power --screenSaver sh "$0" "$@" ;;
    *GNOME*) command -v gnome-session-inhibit >/dev/null 2>&1 && exec gnome-session-inhibit --inhibit suspend:idle --reason "Installing KwickOS" sh "$0" "$@" ;;
  esac
  for i in elogind-inhibit systemd-inhibit; do
    command -v $i >/dev/null 2>&1 && exec $i --what=sleep:idle:handle-lid-switch --who="Install KwickOS" --why="Installing KwickOS" --mode=block sh "$0" "$@"
  done
fi
B=$1; d=$2; shift 2
cd /
wipe() {
  for f in pw luks; do
    [ -f "$d/$f" ] || continue
    shred -u "$d/$f" 2>/dev/null || rm -f "$d/$f"
  done
}
trap wipe EXIT INT TERM HUP
if [ "$(id -u)" = 0 ]; then
  "$B" run "$@" --yes >>"$d/out" 2>&1
elif sudo -n true 2>/dev/null; then
  sudo -n "$B" run "$@" --yes >>"$d/out" 2>&1
else
  pkexec "$B" run "$@" --yes >>"$d/out" 2>&1
fi
rc=$?
wipe
echo "EXIT $rc" >>"$d/out"
