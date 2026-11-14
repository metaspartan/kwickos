# kwick-pen: security toolkit

`kwick-pen` is an optional, Kali-style toolkit for KwickOS. Nothing is preinstalled and the image size cost is the CLI plus the
menu entries (a few kilobytes). Install it with `apt install kwick-pen` on a KwickOS system (it is built by
`scripts/mkpenpkg.sh`), then add the modules you need.

```
kwick-pen list [module]        modules, or one module's tools with their source
kwick-pen status [--machine]   installed state of every module
kwick-pen install [--yes] <module...>
kwick-pen remove <module...>
kwick-pen all [--yes]
```

For authorized security testing only. Use these tools on systems you own or have written permission to test. The first run prints
this notice once.

## Never mix Kali into Debian

Kali Linux is a rolling distribution built on Debian testing. Adding the Kali repositories to a Debian 13 system pulls in
newer libraries and replaces core packages, which breaks the system in ways that are hard to undo. `kwick-pen` never adds Kali
repositories and never will. If a tool is not in Debian 13, it comes from the vendor's own channel (below), pinned to a version
and verified, or it is not offered.

## Where tools come from

1. Debian 13 packages (marked "deb"). Contrib and non-free are enabled for the lookup, packages Debian does not have are skipped
   with a message.
2. Vendor installers and repos with pins: Burp Suite from PortSwigger (version and sha256 pinned), Metasploit and Kismet from
   their own apt repositories (the signing key fingerprint is pinned and checked before the key is trusted).
3. Pinned upstream releases with sha256: ProjectDiscovery and other Go binaries, Ghidra, jadx, radare2, nikto, Responder,
   SecLists, GEF, kerbrute, and the Exploit-DB git commit.
4. `pipx` (isolated environments under `/opt/kwick-pen/pipx`, binaries in `/usr/local/bin`) for Python tools, pinned to a PyPI
   version or a git commit.
5. Flatpak (Flathub) where it is the official channel: OWASP ZAP.

Burp Suite asks you to accept the PortSwigger EULA (`--yes` accepts it non-interactively). Pinned versions live in
`/usr/lib/kwick/pen/pins.env`; update a pin and its sha256 together.

Tools that do not exist for the machine's architecture are skipped cleanly: `kwick-pen list <module>` marks them, `install`
prints a skip line and carries on. Go release binaries, Ghidra, radare2, Metasploit, Kismet and Burp are amd64 and arm64 only, and
kerbrute is amd64 only. riscv64 gets Debian packages and the pure Python, Perl, Ruby and Java tools. Debian itself has no riscv64
build of hashcat, pocl-opencl-icd, guymager or cutycapt, so those are skipped there.

Removing a module removes its own tools; a package that two modules share (for example `python3-impacket` in network and ad) is
removed with whichever module you remove first.

## Modules

Arch: "all" is amd64, arm64 and riscv64 (Debian packages follow Debian's own per-package architecture list).

### recon

| Tool | Source | Arch |
|---|---|---|
| nmap, masscan, arp-scan, netdiscover, whois, dnsrecon, dnsenum, fierce, recon-ng | deb | all |
| amass 5.1.3 | pinned release | amd64, arm64 |
| subfinder 2.17.0 | pinned release | amd64, arm64 |
| httpx 1.12.0 | pinned release | amd64, arm64 |
| theHarvester 4.11.1 | pipx, git commit | all |

### web

| Tool | Source | Arch |
|---|---|---|
| Burp Suite 2026.11 (free edition without a licence) | PortSwigger installer, sha256 | amd64, arm64 |
| OWASP ZAP | Flathub | amd64, arm64 |
| sqlmap, ffuf, gobuster, wfuzz, whatweb, wafw00f, dirb, arjun, testssl.sh, sslscan | deb | all |
| feroxbuster 2.14.0 | pinned release | amd64, arm64 |
| nikto 2.6.1 (Debian has 2.1.5) | pinned tarball | all |
| nuclei 3.11.1, katana 1.8.0 | pinned release | amd64, arm64 |

### network

| Tool | Source | Arch |
|---|---|---|
| Wireshark, tshark, tcpdump, bettercap, ettercap, dsniff, proxychains4, socat, netcat, tor, hping3, tcpflow, ngrep | deb | all |
| Impacket 0.12.0 (python3-impacket) | deb | all |
| Responder 3.2.2.0 | pinned tarball | all |
| NetExec 1.5.1 | pipx, git commit | all |

### passwords

| Tool | Source | Arch |
|---|---|---|
| john, hashcat (with pocl OpenCL), hydra, medusa, ncrack, crunch, cewl, hashid | deb | all |
| SecLists 2026.2 (also linked at `/usr/share/seclists`, about 2 GB unpacked) | pinned tarball | all |

### wireless

| Tool | Source | Arch |
|---|---|---|
| aircrack-ng, wifite, reaver, bully, mdk4, hcxtools, pixiewps, cowpatty, macchanger, wavemon, iw, btscanner, ubertooth | deb | all |
| Kismet | Kismet apt repo (trixie), key fingerprint pinned | amd64, arm64 |

### exploit

| Tool | Source | Arch |
|---|---|---|
| Metasploit Framework | Rapid7 apt repo, key fingerprint pinned | amd64, arm64 |
| searchsploit and Exploit-DB (commit pinned, in `/opt/exploitdb`) | git | all |
| sploitscan, pwntools | deb | all |

### ad

| Tool | Source | Arch |
|---|---|---|
| Impacket, smbclient, smbmap, ldap-utils | deb | all |
| NetExec | pipx | all |
| Certipy 5.1.0 | pipx, PyPI pin | all |
| BloodHound CE collector (bloodhound-ce-python 1.9.1) | pipx, PyPI pin | all |
| BloodHound CE server through bloodhound-cli 0.2.1 (needs Docker) | pinned release | amd64, arm64 |
| kerbrute 1.0.3 | pinned release | amd64 |
| evil-winrm 4.1 | RubyGems, version pin | all |

### re

| Tool | Source | Arch |
|---|---|---|
| gdb, checksec, ltrace, strace, binwalk, upx, qemu-user | deb | all |
| GEF 2026.01 (run `gef`) | pinned file | all |
| Ghidra 12.2 (needs JDK 21, installed from Debian) | pinned release | amd64, arm64 |
| radare2 6.2.6 | pinned .deb | amd64, arm64 |

### forensics

| Tool | Source | Arch |
|---|---|---|
| Sleuth Kit, Autopsy (Debian's 2.24 web version), foremost, testdisk, guymager, yara, python3-yara, exiftool | deb | all |
| Volatility 3 2.28.2 | pipx, PyPI pin | all |

### mobile

| Tool | Source | Arch |
|---|---|---|
| apktool, adb, apksigner | deb | all |
| jadx 1.5.6 | pinned release | all |
| Frida tools 14.13.1, objection 1.12.5 | pipx, PyPI pin | all |

### cloud

| Tool | Source | Arch |
|---|---|---|
| Trivy 0.76.2 | pinned release | amd64, arm64 |
| Prowler 5.49.0, ScoutSuite 5.14.0 | pipx, PyPI pin | all |

### osint

| Tool | Source | Arch |
|---|---|---|
| sherlock, recon-ng, exiftool, cutycapt | deb | all |
| Maigret 0.6.6 | pipx, PyPI pin | all |
| theHarvester | pipx, git commit | all |

### defense

| Tool | Source | Arch |
|---|---|---|
| lynis, rkhunter, chkrootkit, ClamAV, Suricata, yara, fail2ban, auditd, aide, lnav | deb | all |

## Menu

The package adds a "Security" folder to XDG menus (KDE Plasma, and any desktop that reads `applications-merged`) with launchers for
Burp Suite, ZAP, Wireshark, Ghidra, JADX, Metasploit, Autopsy, Kismet and the toolkit manager. A launcher only appears once its tool
is installed (`TryExec`). GNOME lists the same launchers in the overview and search, without a dedicated folder. Hyprland launchers
show them as ordinary applications.

## Not covered

No Kali repositories, no Kali-only tools without an upstream release, and no wrapper for tools that are commercial only. Burp Suite
Professional and Metasploit Pro are licensed products you activate yourself.
