#!/bin/sh
ROOT=$(cd "$(dirname "$0")/.." && pwd)
S="$ROOT/desktop/rootfs/usr/lib/kwick/pipewire-session"
T=$(mktemp -d)
trap 'kill $(cat "$T"/pid.* 2>/dev/null) 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok() { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

mkdir -p "$T/bin" "$T/run"
for d in pipewire wireplumber pipewire-pulse; do
  printf '#!/bin/sh\necho started >> "%s/started.%s"\n' "$T" "$d" > "$T/bin/$d"
  chmod 755 "$T/bin/$d"
done

case_run() {
  rm -f "$T"/started.* "$T/bin/pgrep"
  running=$1
  printf '#!/bin/sh\nfor n in %s; do [ "$2" = "$n" ] && { cat "%s/pid.$n"; exit 0; }; done\nexit 1\n' "$running" "$T" > "$T/bin/pgrep"
  chmod 755 "$T/bin/pgrep"
  for n in $running; do sleep 30 & echo $! > "$T/pid.$n"; done
  XDG_RUNTIME_DIR="$T/run" PATH="$T/bin:$PATH" timeout 10 sh "$S"
  for n in $running; do kill "$(cat "$T/pid.$n")" 2>/dev/null; rm -f "$T/pid.$n"; done
}

case_run ""
[ -f "$T/started.pipewire" ] && [ -f "$T/started.wireplumber" ] && [ -f "$T/started.pipewire-pulse" ] && ok "a fresh login starts all three" || bad "a fresh login did not start pipewire, wireplumber and pipewire-pulse"

case_run "pipewire pipewire-pulse"
[ ! -f "$T/started.pipewire" ] && [ -f "$T/started.wireplumber" ] && ok "a pipewire left from the last session gets its missing wireplumber" || bad "with pipewire still running wireplumber was not started (no session manager: streams never start, the polkit agent hangs)"

case_run "pipewire wireplumber pipewire-pulse"
[ ! -f "$T/started.pipewire" ] && [ ! -f "$T/started.wireplumber" ] && [ ! -f "$T/started.pipewire-pulse" ] && ok "nothing is started twice" || bad "a daemon was started although it was running"
exit $fail
