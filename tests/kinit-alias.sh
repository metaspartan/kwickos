#!/bin/sh
KINIT=${1:?usage: kinit-alias.sh KINIT_BINARY  (run as root in a throwaway container: it writes /etc/systemd/system)}
[ "$(id -u)" = 0 ] || { echo "run as root in a throwaway container"; exit 2; }
[ -e /run/kinit.sock ] && { echo "refusing to run on a system managed by kinit"; exit 2; }
B=$(mktemp -d)
trap 'rm -rf "$B" /usr/lib/systemd/system/kwicktest.service /etc/systemd/system/kwicktest-alias.service /etc/systemd/system/multi-user.target.wants/kwicktest.service' EXIT
for n in systemctl deb-systemd-helper; do ln -s "$KINIT" "$B/$n"; done
mkdir -p /usr/lib/systemd/system
printf '[Unit]\nDescription=test\n[Service]\nExecStart=/bin/true\n[Install]\nWantedBy=multi-user.target\nAlias=kwicktest-alias.service\n' > /usr/lib/systemd/system/kwicktest.service
fail=0
ok() { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

"$B/deb-systemd-helper" enable kwicktest.service
[ "$(readlink /etc/systemd/system/kwicktest-alias.service)" = /usr/lib/systemd/system/kwicktest.service ] && ok "enable creates the Alias= link" || bad "enable did not create /etc/systemd/system/kwicktest-alias.service"
[ -L /etc/systemd/system/multi-user.target.wants/kwicktest.service ] && ok "enable still links WantedBy=" || bad "WantedBy= link missing"
[ "$("$B/systemctl" is-enabled kwicktest-alias)" = enabled ] && ok "the alias resolves to the enabled unit" || bad "is-enabled on the alias is not 'enabled'"
"$B/systemctl" disable kwicktest-alias >/dev/null
[ -e /etc/systemd/system/kwicktest-alias.service ] && bad "disable through the alias left the alias link" || ok "disable through the alias removes the alias link"
[ -e /etc/systemd/system/multi-user.target.wants/kwicktest.service ] && bad "disable through the alias left the WantedBy= link" || ok "disable through the alias removes the WantedBy= link"
exit $fail
