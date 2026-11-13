# Short system summary for interactive login shells.
case $- in *i*) ;; *) return 2>/dev/null || exit 0 ;; esac
[ -n "${KWICK_BANNER_SHOWN:-}" ] && return 0 2>/dev/null
export KWICK_BANNER_SHOWN=1
mem=$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf "%d/%d MiB", (t-a)/1024, t/1024}' /proc/meminfo 2>/dev/null)
ip=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | head -n1)
up=$(awk '{printf "%.1fs", $1}' /proc/uptime)
printf '  \033[1;36m%s\033[0m  kernel %s  up %s  mem %s  ip %s\n\n' "$(cat /etc/kwick-release 2>/dev/null)" "$(uname -r)" "$up" "$mem" "${ip:-none}"