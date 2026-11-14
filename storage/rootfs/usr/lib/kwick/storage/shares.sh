SMB_CONF=/etc/samba/smb.conf
SMB_SHARES=/etc/samba/kwick-shares.conf
NFS_EXPORTS=/etc/exports.d/kwick.exports
AVAHI_SMB=/etc/avahi/services/kwick-smb.service

shares_arch() { echo any; }
shares_desc() { echo "Samba with wsdd2 for Windows and Avahi for macOS discovery, plus the NFS server"; }

shares_state() {
  a=$(pkgs_state samba avahi-daemon)
  b=$(pkgs_state nfs-kernel-server)
  combine_state "$a" "$b"
}

smb_include() {
  [ -f "$SMB_CONF" ] || printf '[global]\n\tworkgroup = WORKGROUP\n\tserver role = standalone server\n\tmap to guest = bad user\n' > "$SMB_CONF"
  [ -f "$SMB_SHARES" ] || : > "$SMB_SHARES"
  grep -q "^[[:space:]]*include = $SMB_SHARES" "$SMB_CONF" || printf '\n[global]\n\tinclude = %s\n' "$SMB_SHARES" >> "$SMB_CONF"
  if ! grep -q 'fruit:' "$SMB_CONF"; then
    awk '
      /^\[global\]/ && !d { print; print "\tvfs objects = catia fruit streams_xattr"; print "\tfruit:metadata = stream"; print "\tfruit:model = RackMac"; print "\tfruit:posix_rename = yes"; print "\tfruit:veto_appledouble = no"; print "\tfruit:nfs_aces = no"; print "\tfruit:wipe_intentionally_left_blank_rfork = yes"; print "\tfruit:delete_empty_adfiles = yes"; print "\tserver min protocol = SMB2_10"; d = 1; next }
      { print }' "$SMB_CONF" > "$SMB_CONF.new" && mv "$SMB_CONF.new" "$SMB_CONF"
  fi
}

avahi_smb() {
  put "$AVAHI_SMB" <<'EOF'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service>
    <type>_smb._tcp</type>
    <port>445</port>
  </service>
  <service>
    <type>_device-info._tcp</type>
    <port>0</port>
    <txt-record>model=RackMac</txt-record>
  </service>
</service-group>
EOF
}

shares_install() {
  apt_get samba samba-common-bin smbclient wsdd2 avahi-daemon nfs-kernel-server || return 1
  smb_include
  avahi_smb
  if [ ! -S /run/dbus/system_bus_socket ] && [ -f /etc/avahi/avahi-daemon.conf ]; then
    sed -i 's/^#\{0,1\}enable-dbus=.*/enable-dbus=warn/' /etc/avahi/avahi-daemon.conf
  fi
  mkdir -p /etc/exports.d
  [ -f "$NFS_EXPORTS" ] || : > "$NFS_EXPORTS"
  load_modules nfsd
  svc_enable smbd nmbd avahi-daemon
  pkg_installed wsdd2 && svc_enable wsdd2
  svc_enable nfs-server
  say "Add a share with: $PROG share add <path> --smb|--nfs [--name N] [--guest] [--ro] [--user U]"
  return 0
}

shares_remove() {
  svc_disable wsdd2 smbd nmbd nfs-server
  rm -f "$AVAHI_SMB"
  apt_remove wsdd2 samba nfs-kernel-server
  return 0
}

smb_reload() {
  have testparm && ! testparm -s "$SMB_CONF" >/dev/null 2>&1 && { testparm -s "$SMB_CONF" 2>&1 | tail -n 5; return 1; }
  if ! svc_active smbd || ! smbcontrol smbd reload-config >/dev/null 2>&1; then svc_restart smbd; fi
  return 0
}

smb_section_drop() {
  awk -v n="[$1]" '
    /^\[/ { skip = ($0 == n) }
    !skip { print }' "$SMB_SHARES" > "$SMB_SHARES.new" && mv "$SMB_SHARES.new" "$SMB_SHARES"
}

path_fstype() {
  awk -v p="$1" '
    { m = $2; if ((p == m || index(p, m == "/" ? "/" : m "/") == 1) && length(m) >= l) { l = length(m); t = $3 } }
    END { print t }' /proc/mounts
}

local_nets() {
  ip -4 route show scope link 2>/dev/null | awk '$1 ~ /\// && $1 !~ /^169\.254/ { print $1 }' | sort -u | tr '\n' ' '
}

share_add() {
  path=${1:-}
  [ -n "$path" ] || die "usage: $PROG share add <path> --smb|--nfs [--name N] [--guest] [--ro] [--user U] [--clients CIDR] [--timemachine]"
  shift
  smb=0; nfs=0; name=""; guest=0; ro=0; users=""; clients=""; tm=0
  while [ $# -gt 0 ]; do
    case $1 in
      --smb) smb=1 ;;
      --nfs) nfs=1 ;;
      --name) name=${2:?--name needs a value}; shift ;;
      --guest) guest=1 ;;
      --ro) ro=1 ;;
      --rw) ro=0 ;;
      --user) users="$users ${2:?--user needs a name}"; shift ;;
      --clients) clients="$clients ${2:?--clients needs a network}"; shift ;;
      --timemachine) tm=1; smb=1 ;;
      *) die "unknown option $1" ;;
    esac
    shift
  done
  [ "$smb" = 1 ] || [ "$nfs" = 1 ] || die "choose --smb, --nfs or both"
  case $path in /*) ;; *) die "give an absolute path" ;; esac
  mkdir -p "$path" || die "cannot create $path"
  [ -n "$name" ] || name=$(basename "$path")
  printf '%s' "$name" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9_. -]{0,79}$' || die "invalid share name: $name"
  if [ "$smb" = 1 ]; then
    pkg_installed samba || shares_install || die "Samba could not be installed"
    smb_include
    smb_section_drop "$name"
    {
      printf '[%s]\n\tpath = %s\n\tbrowseable = yes\n' "$name" "$path"
      if [ "$ro" = 1 ]; then printf '\tread only = yes\n'; else printf '\tread only = no\n'; fi
      if [ "$guest" = 1 ]; then
        printf '\tguest ok = yes\n\tforce user = nobody\n\tforce group = nogroup\n'
        chown nobody:nogroup "$path" 2>/dev/null
        chmod 2775 "$path"
      else
        printf '\tguest ok = no\n'
      fi
      [ -n "$users" ] && printf '\tvalid users =%s\n' "$users"
      printf '\tcreate mask = 0664\n\tdirectory mask = 2775\n'
      [ "$tm" = 1 ] && printf '\tfruit:time machine = yes\n'
      printf '\n'
    } >> "$SMB_SHARES"
    smb_reload || die "the Samba configuration does not validate"
    say "SMB share \\\\$(hostname)\\$name -> $path"
    if [ "$guest" != 1 ]; then
      for u in $users; do
        pdbedit -L 2>/dev/null | grep -q "^$u:" || say "set a Samba password for $u: $PROG share user $u"
      done
      [ -n "$users" ] || say "any Samba user can connect; add one with: $PROG share user <name>"
    fi
  fi
  if [ "$nfs" = 1 ]; then
    pkg_installed nfs-kernel-server || shares_install || die "the NFS server could not be installed"
    [ -n "$clients" ] || clients=$(local_nets)
    [ -n "$clients" ] || die "no local network found, pass --clients <CIDR>"
    mkdir -p /etc/exports.d
    touch "$NFS_EXPORTS"
    awk -v p="$path" '$1 != p' "$NFS_EXPORTS" > "$NFS_EXPORTS.new" && mv "$NFS_EXPORTS.new" "$NFS_EXPORTS"
    opt=rw
    [ "$ro" = 1 ] && opt=ro
    case $(path_fstype "$path") in fuse* | zfs) opt="$opt,fsid=$(($(printf '%s' "$path" | cksum | cut -d' ' -f1) % 1000000 + 1000))" ;; esac
    line=$path
    for c in $clients; do line="$line $c($opt,sync,no_subtree_check,root_squash)"; done
    echo "$line" >> "$NFS_EXPORTS"
    load_modules nfsd
    exportfs -ra || die "exportfs failed"
    say "NFS export $(hostname):$path for $(printf '%s' "$clients" | xargs)"
  fi
}

share_remove() {
  key=${1:?usage: $PROG share remove <name|path>}
  found=0
  if [ -f "$SMB_SHARES" ] && grep -qx "\[$key\]" "$SMB_SHARES"; then
    smb_section_drop "$key"
    smb_reload
    found=1
  fi
  if [ -f "$NFS_EXPORTS" ] && awk -v p="$key" '$1 == p { f = 1 } END { exit !f }' "$NFS_EXPORTS"; then
    awk -v p="$key" '$1 != p' "$NFS_EXPORTS" > "$NFS_EXPORTS.new" && mv "$NFS_EXPORTS.new" "$NFS_EXPORTS"
    exportfs -ra
    found=1
  fi
  [ $found = 1 ] || die "no share named $key"
  say "removed $key; the files stay in place"
}

share_list() {
  machine=${1:-}
  if [ -f "$SMB_SHARES" ]; then
    awk -v m="$machine" '
      /^\[/ { n = substr($0, 2, length($0) - 2); next }
      /^[[:space:]]*path = / { p = $0; sub(/^[[:space:]]*path = /, "", p); if (m != "") print "share|smb|" n "|" p; else printf "smb  %-20s %s\n", n, p }' "$SMB_SHARES"
  fi
  if [ -f "$NFS_EXPORTS" ]; then
    awk -v m="$machine" 'NF >= 2 { c = $2; for (i = 3; i <= NF; i++) c = c " " $i; if (m != "") print "share|nfs|" $1 "|" c; else printf "nfs  %-20s %s\n", $1, c }' "$NFS_EXPORTS"
  fi
  return 0
}

share_user() {
  u=${1:?usage: $PROG share user <name>}
  have smbpasswd || die "Samba is not installed: $PROG install shares"
  getent passwd "$u" >/dev/null || useradd -M -s /usr/sbin/nologin "$u" 2>/dev/null || adduser -D -H -s /sbin/nologin "$u" || die "cannot create the system user $u"
  smbpasswd -a "$u"
}

cmd_share() {
  sub=${1:-list}
  [ $# -gt 0 ] && shift
  case $sub in
    list) share_list "$@" ;;
    add) need_root share add "$@"; share_add "$@" ;;
    remove) need_root share remove "$@"; share_remove "$@" ;;
    user) need_root share user "$@"; share_user "$@" ;;
    *) die "usage: $PROG share list|add|remove|user" ;;
  esac
}
