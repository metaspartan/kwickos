#!/bin/bash
# Compatibility matrix: install real Debian packages on a fresh KwickOS
# container each and run a smoke test. Usage:
#   tests/compat.sh [image] [parallelism]
# Writes a markdown table to stdout and logs to out/compat/<pkg>.log
set -uo pipefail
IMG=${1:-kwickos:dev}
PAR=${2:-6}
LOGDIR=${LOGDIR:-$(mktemp -d /tmp/kwick-compat.XXXX)}
mkdir -p "$LOGDIR"

# package | smoke test
read -r -d '' MATRIX <<'EOF'
curl|curl -sS --version | head -1
wget|wget --version | head -1
ca-certificates|test $(ls /etc/ssl/certs | wc -l) -gt 100 && echo certs ok
python3|python3 -c 'import ssl,sqlite3,json,venv; print("py", __import__("sys").version.split()[0])'
python3-pip|pip3 --version
nginx|nginx -t 2>&1 | tail -1
apache2|apache2ctl -t 2>&1 | tail -1
tzdata|ls -l /etc/localtime
git|git --version
openssh-server|systemctl start ssh && sleep 1 && systemctl is-active ssh && ls -d /run/sshd
redis-server|redis-server --version
postgresql|ls /usr/lib/postgresql/*/bin/postgres && pg_lsclusters
mariadb-server|mariadbd --version
nodejs|node -e 'console.log("node", process.version)'
php-cli|php -r 'echo "php ".PHP_VERSION.PHP_EOL;'
ruby|ruby -e 'puts "ruby #{RUBY_VERSION}"'
golang-go|go version
build-essential|echo 'int main(){return 0;}' > /tmp/t.c && gcc -o /tmp/t /tmp/t.c && /tmp/t && echo gcc ok
vim|vim --version | head -1
htop|htop --version
sudo|sudo -V | head -1
jq|echo '{"a":1}' | jq .a
rsync|rsync --version | head -1
openjdk-21-jre-headless|java -version 2>&1 | head -1
docker.io|dockerd --version
supervisor|supervisord --version
cron|test -x /usr/sbin/cron && echo cron ok
rsyslog|rsyslogd -v | head -1
iproute2|ip -V
bash|bash -c 'declare -A m; m[k]=v; echo bash ${BASH_VERSION} ${m[k]}'
coreutils|ls --version | head -1
EOF

run_one() {
  local pkg=$1 smoke=$2
  local log="$LOGDIR/$pkg.log"
  local t0=$(date +%s)
  docker run --rm "$IMG" sh -c "apt update >/dev/null 2>&1 && apt install -y $pkg; echo \"__RC_INSTALL=\$?\"; $smoke; echo \"__RC_SMOKE=\$?\"; du -smx / 2>/dev/null | cut -f1 | sed 's/^/__SIZE_MB=/'" >"$log" 2>&1
  local t1=$(date +%s)
  local ri=$(grep -o '__RC_INSTALL=[0-9]*' "$log" | cut -d= -f2)
  local rs=$(grep -o '__RC_SMOKE=[0-9]*' "$log" | cut -d= -f2)
  local sz=$(grep -o '__SIZE_MB=[0-9]*' "$log" | cut -d= -f2)
  local out=$(sed -n '/^__RC_INSTALL/,/^__RC_SMOKE/p' "$log" | grep -v '^__' | tail -1 | tr '|' '/' | cut -c1-60)
  [ "${ri:-1}" = 0 ] || out=$(grep -E '^(E:|W: compat)' "$log" | tail -1 | tr '|' '/' | cut -c1-70)
  local status=PASS
  [ "${ri:-1}" = 0 ] && [ "${rs:-1}" = 0 ] || status=FAIL
  echo "| $pkg | $status | $((t1-t0))s | ${sz:-?} MB | ${out} |"
}
export -f run_one
export IMG LOGDIR

echo "| package | result | time | rootfs after | smoke output |"
echo "|---|---|---|---|---|"
echo "$MATRIX" | while IFS='|' read -r pkg smoke; do [ -n "$pkg" ] || continue
  if [ -n "${PKGS:-}" ] && ! echo " $PKGS " | grep -q " $pkg "; then continue; fi
  printf '%s\0%s\0' "$pkg" "$smoke"; done \
  | xargs -0 -n2 -P"$PAR" bash -c 'run_one "$0" "$1"' | sort
