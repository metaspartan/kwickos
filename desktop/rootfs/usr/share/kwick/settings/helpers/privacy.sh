#!/bin/sh
me=$(id -u)
for p in /proc/[0-9]*; do
  [ "$(stat -c %u "$p" 2>/dev/null)" = "$me" ] || continue
  for fd in "$p"/fd/*; do
    case $(readlink "$fd" 2>/dev/null) in
      /dev/video*)
        c=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null | cut -d' ' -f1)
        echo "camera|$(basename "${c:-$(cat "$p/comm")}")|${p#/proc/}"
        break ;;
    esac
  done
done | sort -u -t'|' -k2,2
command -v pw-dump >/dev/null 2>&1 && pw-dump 2>/dev/null | awk '
function val(s) { sub(/^[^:]*: */, "", s); sub(/,$/, "", s); gsub(/"/, "", s); return s }
function flush() {
  if (id == "") return
  if (type == "Node") { cls[id] = mc; name[id] = (app != "" ? app : (bin != "" ? bin : nn)); dev[id] = api; nst[id] = st }
  if (type == "Link" && st == "active") { n++; lo[n] = out; li[n] = inp }
}
/^  \{/ { flush(); id = ""; type = ""; mc = ""; app = ""; bin = ""; nn = ""; api = ""; out = ""; inp = ""; st = ""; next }
/^    "id": / { id = val($0) }
/^    "type": / { type = val($0); sub(/.*Interface:/, "", type) }
/"media.class":/ && mc == "" { mc = val($0) }
/"application.name":/ && app == "" { app = val($0) }
/"application.process.binary":/ && bin == "" { bin = val($0) }
/"node.name":/ && nn == "" { nn = val($0) }
/"device.api":/ && api == "" { api = val($0) }
/"api.v4l2.path":|"api.libcamera.location":/ { api = "camera" }
/"output-node-id":/ { out = val($0) }
/"input-node-id":/ { inp = val($0) }
/^      "state":/ && st == "" { st = val($0) }
END {
  flush()
  for (i = 1; i <= n; i++) {
    s = lo[i]; d = li[i]
    if (cls[d] == "Stream/Input/Audio" && cls[s] ~ /^Audio\/Source/) print "use|microphone|" name[d]
    else if (cls[d] ~ /^Stream\/Input\/Video/ || cls[d] == "Video/Sink") {
      if (dev[s] == "v4l2" || dev[s] == "libcamera" || dev[s] == "camera") print "use|camera|" name[d]
      else print "use|screen|" name[d]
    }
  }
}' | sort -u
v=/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
if [ -r "$v" ]; then
  [ "$(od -An -tu1 -j4 -N1 "$v" | tr -d ' ')" = 1 ] && echo "secureboot|on" || echo "secureboot|off"
elif [ -d /sys/firmware/efi ]; then
  echo "secureboot|unknown"
else
  echo "secureboot|bios"
fi
root=$(findmnt -n -o SOURCE / 2>/dev/null)
if lsblk -s -n -o TYPE "$root" 2>/dev/null | grep -q crypt; then echo "encryption|on"; else echo "encryption|off"; fi
command -v fwupdmgr >/dev/null 2>&1 && echo "fwupd|yes" || echo "fwupd|no"
command -v flatpak >/dev/null 2>&1 && for t in devices location screenshot background notifications; do
  flatpak permissions "$t" 2>/dev/null | awk -F'\t' -v t="$t" 'NF>=4 && $1==t {gsub(/^ +| +$/,"",$2); gsub(/^ +| +$/,"",$3); gsub(/^ +| +$/,"",$4); print "perm|" t "|" $2 "|" $3 "|" $4}'
done
[ -x /usr/libexec/geoclue ] && echo "location|yes" || echo "location|no"
