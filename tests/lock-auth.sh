#!/bin/sh
ROOT=${ROOT:-}
fail=0
ok() { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

stat_of() { stat -c '%a %U:%G' "$ROOT$1" 2>/dev/null; }

h=$(stat_of /usr/sbin/unix_chkpwd)
case $h in
  "2755 root:shadow"|"4755 root:root") ok "unix_chkpwd is $h" ;;
  *) bad "unix_chkpwd is '${h:-missing}', expected 2755 root:shadow; pam_unix cannot read /etc/shadow for unprivileged lock screens (swaylock, hyprlock, kscreenlocker, gdm)" ;;
esac

s=$(stat_of /etc/shadow)
case $s in
  "640 root:shadow"|"600 root:root"|"400 root:root") ok "/etc/shadow is $s" ;;
  *) bad "/etc/shadow is '${s:-missing}', expected 640 root:shadow" ;;
esac

gid=$(sed -n 's/^shadow:[^:]*:\([0-9]*\):.*/\1/p' "$ROOT/etc/group")
[ -n "$gid" ] && ok "shadow group is gid $gid" || bad "no shadow group in /etc/group"

for d in /etc /etc/pam.d /usr /usr/lib /usr/bin /usr/sbin; do
  m=$(stat -c '%a' "$ROOT$d" 2>/dev/null)
  case $m in
    *[2367]) bad "$d is mode $m, world-writable" ;;
  esac
done
for f in /etc/pam.d/*; do
  [ -f "$ROOT$f" ] || continue
  m=$(stat -c '%a' "$ROOT$f")
  case $m in
    *[2367]) bad "$f is mode $m, world-writable" ;;
  esac
done

modules() {
  svc=$1; seen=$2
  case " $seen " in *" $svc "*) return ;; esac
  f="$ROOT/etc/pam.d/$svc"
  [ -f "$f" ] || { echo "MISSING:$svc"; return; }
  awk '{ sub(/#.*/, ""); if (NF == 0 || $1 ~ /^-/) next
         if ($1 == "@include") { print "INC:" $2; next }
         i = 2
         if ($2 ~ /^\[/) { while ($i !~ /\]$/) i++ }
         if ($i == "include" || $i == "substack") { print "INC:" $(i + 1); next }
         print "MODULE:" $(i + 1) }' "$f" | while IFS=: read -r kind name; do
    case $kind in
      INC) modules "$name" "$seen $svc" ;;
      MODULE) echo "MODULE:$name" ;;
    esac
  done
}

for svc in swaylock login sddm sudo other; do
  [ -f "$ROOT/etc/pam.d/$svc" ] || { [ "$svc" = swaylock ] && continue; bad "/etc/pam.d/$svc missing"; continue; }
  miss=
  for m in $(modules "$svc" "" | sed -n 's/^MODULE://p' | sort -u); do
    case $m in
      /*) [ -e "$ROOT$m" ] || miss="$miss $m" ;;
      *)
        found=
        for p in "$ROOT"/usr/lib/*/security/"$m" "$ROOT"/lib/*/security/"$m" "$ROOT"/usr/lib/security/"$m"; do
          [ -e "$p" ] && found=1
        done
        [ -n "$found" ] || miss="$miss $m"
        ;;
    esac
  done
  [ -z "$miss" ] && ok "pam service $svc resolves to installed modules" || bad "pam service $svc needs missing modules:$miss"
done

grep -q 'pam_unix.so' "$ROOT/etc/pam.d/common-auth" && ok "common-auth uses pam_unix" || bad "common-auth has no pam_unix"

if [ -n "${KWICK_TEST_USER:-}" ] && [ -n "${KWICK_TEST_PASSWORD:-}" ] && [ "$(id -u)" != 0 ]; then
  printf '%s\0' "$KWICK_TEST_PASSWORD" | "$ROOT/usr/sbin/unix_chkpwd" "$KWICK_TEST_USER" nullok >/dev/null 2>&1
  [ $? -eq 0 ] && ok "unix_chkpwd verifies $KWICK_TEST_USER as an unprivileged process" || bad "unix_chkpwd rejected the correct password for $KWICK_TEST_USER as an unprivileged process"
  printf '%s\0' "not-$KWICK_TEST_PASSWORD" | "$ROOT/usr/sbin/unix_chkpwd" "$KWICK_TEST_USER" nullok >/dev/null 2>&1
  [ $? -ne 0 ] && ok "unix_chkpwd rejects a wrong password" || bad "unix_chkpwd accepted a wrong password"
fi

exit $fail
