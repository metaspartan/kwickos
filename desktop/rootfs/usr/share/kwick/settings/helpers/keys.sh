#!/bin/sh
command -v kwick-keys >/dev/null 2>&1 || { echo '{"error":"kwick-keys is not installed"}'; exit 1; }
op=${1:-list}
[ $# -gt 0 ] && shift
case $op in
  list) exec kwick-keys list --json ;;
  set) exec kwick-keys set --json "$@" 2>&1 ;;
  check) exec kwick-keys check "$@" 2>&1 ;;
  reset) kwick-keys reset --json "$@" >/dev/null 2>&1; exec kwick-keys list --json ;;
  record)
    if [ "${1:-}" = stop ]; then
      exec kwick-keys inhibit --stop
    fi
    setsid kwick-keys inhibit "${1:-30}" >/dev/null 2>&1 </dev/null &
    exit 0 ;;
  export)
    [ -n "${1:-}" ] || { echo "no file chosen"; exit 2; }
    exec kwick-keys export "$1" 2>&1 ;;
  import)
    [ -n "${1:-}" ] || { echo "no file chosen"; exit 2; }
    exec kwick-keys import "$1" 2>&1 ;;
  *) echo "usage: keys.sh list|set|check|reset|record [stop]|export FILE|import FILE" >&2; exit 2 ;;
esac
