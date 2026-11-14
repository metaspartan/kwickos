ALL_ARCHES="amd64 arm64 riscv64"
GO_ARCHES="amd64 arm64"

bin_remove() { rm -f "$BINDIR/$1"; return 0; }

opt_remove() { rm -rf "${OPT:?}/$1"; return 0; }

pin_subfinder_arch() { echo "$GO_ARCHES"; }
pin_subfinder_src() { echo "ProjectDiscovery release, sha256 pinned"; }
pin_subfinder_install() { bin_archive subfinder SUBFINDER_URL SUBFINDER_SHA256 subfinder; }
pin_subfinder_remove() { bin_remove subfinder; }

pin_amass_arch() { echo "$GO_ARCHES"; }
pin_amass_src() { echo "OWASP Amass release, sha256 pinned"; }
pin_amass_install() { bin_archive amass AMASS_URL AMASS_SHA256 amass; }
pin_amass_remove() { bin_remove amass; }

pin_httpx_arch() { echo "$GO_ARCHES"; }
pin_httpx_src() { echo "ProjectDiscovery release, sha256 pinned"; }
pin_httpx_install() { bin_archive httpx HTTPX_URL HTTPX_SHA256 httpx; }
pin_httpx_remove() { bin_remove httpx; }

pin_katana_arch() { echo "$GO_ARCHES"; }
pin_katana_src() { echo "ProjectDiscovery release, sha256 pinned"; }
pin_katana_install() { bin_archive katana KATANA_URL KATANA_SHA256 katana; }
pin_katana_remove() { bin_remove katana; }

pin_nuclei_arch() { echo "$GO_ARCHES"; }
pin_nuclei_src() { echo "ProjectDiscovery release, sha256 pinned"; }
pin_nuclei_install() { bin_archive nuclei NUCLEI_URL NUCLEI_SHA256 nuclei; }
pin_nuclei_remove() { bin_remove nuclei; }

pin_feroxbuster_arch() { echo "$GO_ARCHES"; }
pin_feroxbuster_src() { echo "upstream release, sha256 pinned"; }
pin_feroxbuster_install() { bin_archive feroxbuster FEROXBUSTER_URL FEROXBUSTER_SHA256 feroxbuster; }
pin_feroxbuster_remove() { bin_remove feroxbuster; }

pin_trivy_arch() { echo "$GO_ARCHES"; }
pin_trivy_src() { echo "Aqua Security release, sha256 pinned"; }
pin_trivy_install() { bin_archive trivy TRIVY_URL TRIVY_SHA256 trivy; }
pin_trivy_remove() { bin_remove trivy; }

pin_kerbrute_arch() { echo amd64; }
pin_kerbrute_src() { echo "upstream release, sha256 pinned (amd64 only)"; }
pin_kerbrute_install() { bin_plain kerbrute KERBRUTE_URL KERBRUTE_SHA256; }
pin_kerbrute_remove() { bin_remove kerbrute; }

pin_bloodhound_cli_arch() { echo "$GO_ARCHES"; }
pin_bloodhound_cli_src() { echo "SpecterOps release, sha256 pinned (runs BloodHound CE in Docker)"; }
pin_bloodhound_cli_install() {
  bin_archive bloodhound-cli BLOODHOUND_CLI_URL BLOODHOUND_CLI_SHA256 bloodhound-cli || return 1
  command -v docker >/dev/null 2>&1 || say "bloodhound-cli needs Docker: install docker.io, then run 'bloodhound-cli install'."
  return 0
}
pin_bloodhound_cli_remove() { bin_remove bloodhound-cli; }

pin_radare2_arch() { echo "$GO_ARCHES"; }
pin_radare2_src() { echo "radare2 release .deb, sha256 pinned"; }
pin_radare2_install() {
  url=$(pv RADARE2_URL)
  sha=$(pv RADARE2_SHA256)
  [ -n "$url" ] || return 1
  t=$(mktmp)
  fetch_verify "$url" "$sha" "$t/radare2.deb" || { rm -rf "$t"; return 1; }
  apt_ready
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$t/radare2.deb"
  r2rc=$?
  rm -rf "$t"
  return $r2rc
}
pin_radare2_remove() { apt_remove radare2; }

pin_jadx_arch() { echo "$ALL_ARCHES"; }
pin_jadx_src() { echo "skylot/jadx release, sha256 pinned (Java)"; }
pin_jadx_install() {
  apt_get default-jre || return 1
  opt_archive jadx "$JADX_URL" "$JADX_SHA256" || return 1
  chmod 755 "$OPT"/jadx/bin/*
  link_bin "$OPT/jadx/bin/jadx" jadx
  link_bin "$OPT/jadx/bin/jadx-gui" jadx-gui
}
pin_jadx_remove() { rm -f "$BINDIR/jadx" "$BINDIR/jadx-gui"; opt_remove jadx; }

pin_ghidra_arch() { echo "$GO_ARCHES"; }
pin_ghidra_src() { echo "NSA release zip, sha256 pinned (needs JDK 21)"; }
pin_ghidra_install() {
  apt_get openjdk-21-jdk unzip || return 1
  opt_archive ghidra "$GHIDRA_URL" "$GHIDRA_SHA256" || return 1
  link_bin "$OPT/ghidra/ghidraRun" ghidra
}
pin_ghidra_remove() { rm -f "$BINDIR/ghidra"; opt_remove ghidra; }

pin_gef_arch() { echo "$ALL_ARCHES"; }
pin_gef_src() { echo "hugsy/gef tag, sha256 pinned"; }
pin_gef_install() {
  apt_get gdb || return 1
  t=$(mktmp)
  fetch_verify "$GEF_URL" "$GEF_SHA256" "$t/gef.py" || { rm -rf "$t"; return 1; }
  install -D -m 644 "$t/gef.py" /usr/share/gef/gef.py
  rm -rf "$t"
  put "$BINDIR/gef" <<'EOF'
#!/bin/sh
exec gdb -q -ex 'source /usr/share/gef/gef.py' "$@"
EOF
  chmod 755 "$BINDIR/gef"
}
pin_gef_remove() { rm -rf /usr/share/gef "$BINDIR/gef"; return 0; }

pin_nikto_arch() { echo "$ALL_ARCHES"; }
pin_nikto_src() { echo "sullo/nikto 2.6.1 tarball, sha256 pinned (Debian ships 2.1.5)"; }
pin_nikto_install() {
  apt_get perl libnet-ssleay-perl openssl || return 1
  opt_archive nikto "$NIKTO_URL" "$NIKTO_SHA256" || return 1
  put "$BINDIR/nikto" <<EOF
#!/bin/sh
exec perl $OPT/nikto/program/nikto.pl "\$@"
EOF
  chmod 755 "$BINDIR/nikto"
}
pin_nikto_remove() { bin_remove nikto; opt_remove nikto; }

pin_responder_arch() { echo "$ALL_ARCHES"; }
pin_responder_src() { echo "lgandx/Responder tag, sha256 pinned"; }
pin_responder_install() {
  apt_get python3 python3-netifaces python3-aioquic || return 1
  opt_archive responder "$RESPONDER_URL" "$RESPONDER_SHA256" || return 1
  put "$BINDIR/responder" <<EOF
#!/bin/sh
cd $OPT/responder && exec python3 ./Responder.py "\$@"
EOF
  chmod 755 "$BINDIR/responder"
}
pin_responder_remove() { bin_remove responder; opt_remove responder; }

pin_seclists_arch() { echo "$ALL_ARCHES"; }
pin_seclists_src() { echo "danielmiessler/SecLists 2026.2 tarball, sha256 pinned (large)"; }
pin_seclists_install() {
  say "SecLists is large (about 2 GB unpacked)."
  opt_archive seclists "$SECLISTS_URL" "$SECLISTS_SHA256" || return 1
  ln -sfn "$OPT/seclists" /usr/share/seclists
  mkdir -p /usr/share/wordlists
  ln -sfn "$OPT/seclists" /usr/share/wordlists/seclists
}
pin_seclists_remove() { rm -f /usr/share/seclists /usr/share/wordlists/seclists; opt_remove seclists; }

pin_burpsuite_arch() { echo "$GO_ARCHES"; }
pin_burpsuite_src() { echo "PortSwigger installer $BURP_VERSION, sha256 pinned"; }
pin_burpsuite_install() {
  url=$(pv BURP_URL)
  sha=$(pv BURP_SHA256)
  [ -n "$url" ] || return 1
  say "Burp Suite is PortSwigger software. Installing it means you accept the PortSwigger EULA (https://portswigger.net/burp/eula)."
  confirm "Accept the Burp Suite EULA and install Burp Suite $BURP_VERSION?" || return 1
  t=$(mktmp)
  fetch_verify "$url" "$sha" "$t/burp.sh" || { rm -rf "$t"; return 1; }
  rm -rf "${OPT:?}/burpsuite"
  mkdir -p "$OPT/burpsuite"
  sh "$t/burp.sh" -q -dir "$OPT/burpsuite" >/dev/null 2>&1
  burprc=$?
  rm -rf "$t"
  exe=$(find "$OPT/burpsuite" -maxdepth 1 -type f -perm -u+x -name 'BurpSuite*' | head -n 1)
  if [ $burprc -ne 0 ] || [ -z "$exe" ]; then warn "Burp Suite installer failed"; return 1; fi
  link_bin "$exe" burpsuite
}
pin_burpsuite_remove() { bin_remove burpsuite; opt_remove burpsuite; }

pin_exploitdb_arch() { echo "$ALL_ARCHES"; }
pin_exploitdb_src() { echo "Exploit-DB git, commit pinned (searchsploit)"; }
pin_exploitdb_install() {
  ensure_tools git || return 1
  rm -rf /opt/exploitdb
  git init -q /opt/exploitdb || return 1
  git -C /opt/exploitdb fetch -q --depth 1 "$EXPLOITDB_REPO" "$EXPLOITDB_COMMIT" || { rm -rf /opt/exploitdb; return 1; }
  git -C /opt/exploitdb checkout -q FETCH_HEAD || { rm -rf /opt/exploitdb; return 1; }
  link_bin /opt/exploitdb/searchsploit searchsploit
}
pin_exploitdb_remove() { bin_remove searchsploit; rm -rf /opt/exploitdb; return 0; }

pin_metasploit_arch() { echo "$GO_ARCHES"; }
pin_metasploit_src() { echo "Rapid7 apt repo, signing key fingerprint pinned"; }
pin_metasploit_install() {
  vendor_repo metasploit "$METASPLOIT_KEY_URL" "$METASPLOIT_KEY_FPR" "$METASPLOIT_REPO" lucid || return 1
  apt_get metasploit-framework
}
pin_metasploit_remove() { apt_remove metasploit-framework; vendor_repo_drop metasploit; }

pin_kismet_arch() { echo "$GO_ARCHES"; }
pin_kismet_src() { echo "Kismet apt repo (trixie), signing key fingerprint pinned"; }
pin_kismet_install() {
  vendor_repo kismet "$KISMET_KEY_URL" "$KISMET_KEY_FPR" "$KISMET_REPO" trixie || return 1
  apt_get kismet
}
pin_kismet_remove() { apt_remove kismet; vendor_repo_drop kismet; }

pin_netexec_arch() { echo "$ALL_ARCHES"; }
pin_netexec_src() { echo "pipx, upstream git commit pinned"; }
pin_netexec_install() {
  apt_get build-essential python3-dev libffi-dev libssl-dev libkrb5-dev || return 1
  pipx_add netexec "$NETEXEC_SPEC"
}
pin_netexec_remove() { pipx_del netexec; }

pin_theharvester_arch() { echo "$ALL_ARCHES"; }
pin_theharvester_src() { echo "pipx, upstream git commit pinned"; }
pin_theharvester_install() { pipx_add theharvester "$THEHARVESTER_SPEC"; }
pin_theharvester_remove() { pipx_del theharvester; }

pin_volatility3_arch() { echo "$ALL_ARCHES"; }
pin_volatility3_src() { echo "pipx, PyPI version pinned"; }
pin_volatility3_install() { pipx_add volatility3 "$VOLATILITY3_SPEC"; }
pin_volatility3_remove() { pipx_del volatility3; }

pin_frida_tools_arch() { echo "$ALL_ARCHES"; }
pin_frida_tools_src() { echo "pipx, PyPI version pinned"; }
pin_frida_tools_install() { pipx_add frida-tools "$FRIDA_TOOLS_SPEC"; }
pin_frida_tools_remove() { pipx_del frida-tools; }

pin_objection_arch() { echo "$ALL_ARCHES"; }
pin_objection_src() { echo "pipx, PyPI version pinned"; }
pin_objection_install() { pipx_add objection "$OBJECTION_SPEC"; }
pin_objection_remove() { pipx_del objection; }

pin_prowler_arch() { echo "$ALL_ARCHES"; }
pin_prowler_src() { echo "pipx, PyPI version pinned"; }
pin_prowler_install() { pipx_add prowler "$PROWLER_SPEC"; }
pin_prowler_remove() { pipx_del prowler; }

pin_scoutsuite_arch() { echo "$ALL_ARCHES"; }
pin_scoutsuite_src() { echo "pipx, PyPI version pinned"; }
pin_scoutsuite_install() { pipx_add scoutsuite "$SCOUTSUITE_SPEC"; }
pin_scoutsuite_remove() { pipx_del scoutsuite; }

pin_certipy_arch() { echo "$ALL_ARCHES"; }
pin_certipy_src() { echo "pipx, PyPI version pinned"; }
pin_certipy_install() { pipx_add certipy-ad "$CERTIPY_SPEC"; }
pin_certipy_remove() { pipx_del certipy-ad; }

pin_maigret_arch() { echo "$ALL_ARCHES"; }
pin_maigret_src() { echo "pipx, PyPI version pinned"; }
pin_maigret_install() { pipx_add maigret "$MAIGRET_SPEC"; }
pin_maigret_remove() { pipx_del maigret; }

pin_bloodhound_py_arch() { echo "$ALL_ARCHES"; }
pin_bloodhound_py_src() { echo "pipx, PyPI version pinned (BloodHound CE collector)"; }
pin_bloodhound_py_install() { pipx_add bloodhound-ce "$BLOODHOUND_PY_SPEC"; }
pin_bloodhound_py_remove() { pipx_del bloodhound-ce; }

pin_evil_winrm_arch() { echo "$ALL_ARCHES"; }
pin_evil_winrm_src() { echo "RubyGems, version pinned"; }
pin_evil_winrm_install() {
  apt_get ruby ruby-dev build-essential libkrb5-dev || return 1
  gem install --no-document -n "$BINDIR" -v "$EVIL_WINRM_VERSION" evil-winrm
}
pin_evil_winrm_remove() {
  command -v gem >/dev/null 2>&1 && gem uninstall -x -a -q evil-winrm >/dev/null 2>&1
  return 0
}
