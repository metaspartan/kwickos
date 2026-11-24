#!/bin/bash
set -uo pipefail
SRC=${SRC:-$(cd "$(dirname "$0")/.." && pwd)}
export SRC
for t in dpkg-deb python3 md5sum; do command -v $t >/dev/null || { echo "need $t (run it in kwick-builder)"; exit 2; }; done
. "$SRC/scripts/deb.sh"
VER=$(kwick_version)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fail=0
ok() { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }
field() { dpkg-deb -f "$1" "$2"; }

export OUT=$W/out
mkdir -p "$OUT/amd64/userland" "$OUT/amd64/kernel-virt"
B=$(type -P true)
case $(od -An -tx1 -j18 -N2 "$B" | tr -d ' \n') in 3e00) ;; *) echo "this test needs an x86-64 host"; exit 2 ;; esac
cp "$B" "$OUT/amd64/userland/kinit"; cp "$B" "$OUT/amd64/userland/kpkg"
K=$OUT/amd64/kernel-virt
echo 7.3.9-kwick > "$K/version"; echo kernel > "$K/vmlinuz"; echo '# config' > "$K/config"
bash "$SRC/scripts/mkkernelpkg.sh" amd64 virt >/dev/null
bash "$SRC/scripts/mkupdatepkg.sh" >/dev/null
bash "$SRC/scripts/mkcorepkg.sh" amd64 >/dev/null
P=$OUT/repo/pool/main
KD=$(ls "$P"/linux-image-kwick-virt_*.deb); UD=$(ls "$P"/kwick-update_*.deb); CD=$(ls "$P"/kwick-core_*.deb)

[ "$(field "$KD" Version)" = "7.3.9-2" ] && ok "kernel packages carry revision -2, so systems on the same kernel get the dependency once" || bad "kernel version $(field "$KD" Version)"
[ "$(field "$KD" Pre-Depends)" = "kwick-update (>= $VER)" ] && ok "kernel pre-depends on kwick-update (>= $VER)" || bad "kernel Pre-Depends: '$(field "$KD" Pre-Depends)'"
[ "$(field "$UD" Depends)" = "kwick-core (>= $VER)" ] && ok "kwick-update depends on kwick-core (>= $VER)" || bad "kwick-update Depends: '$(field "$UD" Depends)'"
[ -z "$(field "$CD" Depends)$(field "$CD" Pre-Depends)" ] && ok "kwick-core depends on nothing, so the chain has no cycle" || bad "kwick-core has dependencies"
for f in "$SRC"/scripts/mkkernelhdrpkg.sh "$SRC"/scripts/mknvidiapkg.sh "$SRC"/scripts/mkzfspkg.sh; do
  grep -q 'KVER-1' "$f" && bad "$(basename "$f") still pins the image package to revision -1" || ok "$(basename "$f") pins the kernel through kernel_deb_version"
done
grep -q 'Pre-Depends: kwick-update' "$SRC/scripts/mkapplepkg.sh" && ok "the Asahi kernel pre-depends on kwick-update too" || bad "mkapplepkg.sh has no Pre-Depends on kwick-update"

R=$W/root
mkdir -p "$R/var/lib/dpkg/info" "$R/usr/sbin" "$R/usr/bin" "$R/etc"
cp "$B" "$R/usr/sbin/kinit"; cp "$B" "$R/usr/bin/kpkg"
printf 'Package: kwick-base\nStatus: install ok installed\nVersion: %s\nArchitecture: amd64\nEssential: yes\nX-Kwick-Base: yes\nProvides: dpkg (= 1.22.21), kinit, kpkg\nDescription: base\n' "$VER" > "$R/var/lib/dpkg/status"
for d in "$CD" "$UD" "$KD"; do deb_register "$R" "$d" >/dev/null; done
deb_core_links "$R"
[ "$(stat -c %i "$R/usr/bin/kpkg")" = "$(stat -c %i "$R/usr/lib/kwick/core/kpkg")" ] && ok "the image keeps one copy of kpkg (hard link)" || bad "kwick-core's kpkg is a second copy"
out=$(deb_check_deps "$R") && ok "an image with kernel, kwick-update and kwick-core registered is consistent" || bad "unexpected unmet dependencies: $out"
for p in kwick-core kwick-update linux-image-kwick-virt; do
  [ -s "$R/var/lib/dpkg/info/$p.list" ] && grep -q "^Package: $p$" "$R/var/lib/dpkg/status" || bad "$p is not registered"
done
grep -q '^/usr/sbin/kwick-update$' "$R/var/lib/dpkg/info/kwick-update.list" && ok "registration records the file list" || bad "kwick-update.list lacks /usr/sbin/kwick-update"
[ -x "$R/var/lib/dpkg/info/kwick-update.postinst" ] && ok "registration keeps the maintainer scripts" || bad "kwick-update.postinst missing"

R2=$W/root2
mkdir -p "$R2/var/lib/dpkg/info"
cp "$R/var/lib/dpkg/status" "$W/status.full"
awk 'BEGIN { RS = ""; ORS = "\n\n" } !/^Package: kwick-update\n/' "$W/status.full" > "$R2/var/lib/dpkg/status"
out=$(deb_check_deps "$R2") && bad "a kernel without kwick-update passed the check" || { echo "$out" | grep -q 'linux-image-kwick-virt.*Pre-Depends: kwick-update' && ok "the check names a kernel registered without kwick-update" || bad "wrong report: $out"; }
sed -i "s/^Version: $VER$/Version: 0.6.5/" "$R2/var/lib/dpkg/status"
printf '\nPackage: kwick-update\nStatus: install ok installed\nVersion: 0.6.5\nArchitecture: all\nDepends: kwick-core\nDescription: old\n' >> "$R2/var/lib/dpkg/status"
out=$(deb_check_deps "$R2") && bad "an old kwick-update satisfied (>= $VER)" || ok "versioned dependencies are compared (0.6.5 does not satisfy >= $VER)"

python3 -I - "$SRC/scripts/dpkg-depcheck.py" <<'PY' && ok "Debian version ordering in dpkg-depcheck.py" || bad "dpkg-depcheck.py version ordering"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("dc", sys.argv[1])
dc = importlib.util.module_from_spec(spec); spec.loader.exec_module(dc)
cases = [("0.7.1-1+kwick1", "0.7.1-1", 1), ("0.7.1-1+kwick1", "0.7.1-1+deb13u1", 1), ("1.0~rc1", "1.0", -1), ("1:0.1", "9.9", 1),
         ("7.3.6-2", "7.3.6-1", 1), ("0.7.10", "0.7.9", 1), ("1.0", "1.0-0", 0), ("2.41-5", "2.41-5", 0), ("1.0a", "1.0", 1)]
bad = [(a, b, w) for a, b, w in cases if (dc.vercmp(a, b) > 0) - (dc.vercmp(a, b) < 0) != w]
print(bad) if bad else None
sys.exit(1 if bad else 0)
PY

E=$W/conf
mkdir -p "$E/DEBIAN" "$E/etc/xdg" "$E/etc/skel/.config" "$E/usr/share/x"
echo a > "$E/etc/xdg/kwinrc"; echo b > "$E/etc/skel/.config/rc"; echo c > "$E/usr/share/x/f"
deb_conffiles "$E"
[ "$(cat "$E/DEBIAN/conffiles")" = /etc/xdg/kwinrc ] && ok "conffiles are the /etc files outside /etc/skel" || bad "conffiles: $(cat "$E/DEBIAN/conffiles")"
deb_control "$E" kwick-conftest "$VER" all misc <<EOF
Description: test
EOF
dpkg-deb --root-owner-group -b "$E" "$W/conftest.deb" >/dev/null
R3=$W/root3; mkdir -p "$R3/var/lib/dpkg/info"; : > "$R3/var/lib/dpkg/status"
deb_register "$R3" "$W/conftest.deb" >/dev/null
grep -q "^ /etc/xdg/kwinrc $(echo a | md5sum | cut -d' ' -f1)$" "$R3/var/lib/dpkg/status" && ok "registration records conffile checksums, so upgrades see unmodified files" || bad "no Conffiles in the registered stanza"

H=$SRC/desktop/rootfs/usr/share/kwick/conffiles.md5
missing=0
while read -r f; do
  p=${f#"$SRC/desktop/rootfs"}
  grep -qxF "$(sed 's/\r$//' "$f" | md5sum | cut -d' ' -f1)  $p" "$H" || { echo "      $p: current version not in conffiles.md5"; missing=1; }
done < <(find "$SRC/desktop/rootfs/etc" -type f ! -path '*/etc/skel/*')
[ $missing = 0 ] && ok "conffiles.md5 knows the shipped version of every desktop /etc file" || bad "conffiles.md5 is missing versions (add them; older versions must stay)"

PI=$W/postinst
sed -n "/^deb_script \"\$P\" postinst <<'EOF'$/,/^EOF$/p" "$SRC/scripts/mkdesktoppkg.sh" | sed '1d;$d' > "$PI"
grep -q 'FIRST=1' "$PI" && grep -q '\[ \$FIRST = 1 \] && ! id kwick' "$PI" && grep -q '\[ \$FIRST = 0 \] || \[ -f /etc/sddm.conf.d/20-autologin.conf \]' "$PI" \
  && ok "adopting an installed desktop creates no kwick user and no autologin" || bad "the desktop postinst creates the live user or autologin on adoption"
F=$W/fix
mkdir -p "$F/etc/xdg" "$F/info"
printf 'old\n' > "$F/etc/xdg/kwinrc"; printf 'new\n' > "$F/etc/xdg/kwinrc.dpkg-dist"
printf 'mine\n' > "$F/etc/xdg/kdeglobals"; printf 'new\n' > "$F/etc/xdg/kdeglobals.dpkg-dist"
printf '%s  %s\n' "$(printf 'old\n' | md5sum | cut -d' ' -f1)" "$F/etc/xdg/kwinrc" "$(printf 'x\n' | md5sum | cut -d' ' -f1)" "$F/etc/xdg/kdeglobals" > "$F/hist"
printf '%s\n' "$F/etc/xdg/kwinrc" "$F/etc/xdg/kdeglobals" > "$F/info/kwick-desktop.conffiles"
sed -n '/^H=\/usr\/share\/kwick\/conffiles.md5$/,/^fi$/p' "$PI" | sed -e "s|^H=.*|H=$F/hist|" -e "s|/var/lib/dpkg/info/kwick-desktop.conffiles|$F/info/kwick-desktop.conffiles|g" > "$F/fix.sh"
sh "$F/fix.sh" > "$F/out"
[ "$(cat "$F/etc/xdg/kwinrc")" = new ] && [ ! -e "$F/etc/xdg/kwinrc.dpkg-dist" ] && ok "an /etc file that matches a shipped version is updated" || bad "pristine conffile was not updated"
[ "$(cat "$F/etc/xdg/kdeglobals")" = mine ] && [ -e "$F/etc/xdg/kdeglobals.dpkg-dist" ] && grep -q 'kept your changes' "$F/out" && ok "an /etc file the user changed is kept, the new one is .dpkg-dist" || bad "user's conffile was replaced"

grep -q 'Depends: \\1, kwick-update' "$SRC/scripts/mkcarrierpkg.sh" && grep -q 'a Depends: kwick-update' "$SRC/scripts/mkcarrierpkg.sh" && ok "the carrier package adds Depends: kwick-update" || bad "mkcarrierpkg.sh does not add the dependency"
grep -qw zsh-autosuggestions "$SRC/desktop/packages.list" && ok "the carrier package is on every desktop image (desktop/packages.list)" || bad "zsh-autosuggestions left desktop/packages.list: pick another carrier"
grep -q 'adopt-desktop --wait' "$SRC/scripts/mkupdatepkg.sh" && grep -q '^adopt-desktop) cmd_adopt' "$SRC/rootfs/usr/sbin/kwick-update" && ok "kwick-update adopts an unregistered desktop" || bad "no desktop adoption in kwick-update"
exit $fail
