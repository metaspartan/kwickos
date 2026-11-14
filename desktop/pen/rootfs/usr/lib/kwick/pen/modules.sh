MODULES="recon web network passwords wireless exploit ad re forensics mobile cloud osint defense"

recon_desc() { echo "Discovery and enumeration: nmap, masscan, amass, subfinder, theHarvester, recon-ng"; }
recon_items() {
  echo "apt:nmap apt:masscan apt:arp-scan apt:netdiscover apt:whois apt:dnsrecon apt:dnsenum apt:fierce apt:recon-ng"
  echo "pin:amass pin:subfinder pin:httpx pin:theharvester"
}

web_desc() { echo "Web testing: Burp Suite, ZAP, sqlmap, ffuf, gobuster, feroxbuster, nikto, nuclei, wfuzz"; }
web_items() {
  echo "pin:burpsuite fp:org.zaproxy.ZAP apt:sqlmap apt:ffuf apt:gobuster apt:wfuzz apt:whatweb apt:wafw00f apt:dirb apt:arjun"
  echo "apt:testssl.sh apt:sslscan pin:feroxbuster pin:nikto pin:nuclei pin:katana"
}

network_desc() { echo "Network attacks and capture: Wireshark, tshark, tcpdump, bettercap, Responder, NetExec, Impacket"; }
network_items() {
  echo "apt:wireshark apt:tshark apt:tcpdump apt:bettercap apt:ettercap-text-only apt:dsniff apt:proxychains4 apt:socat apt:netcat-openbsd"
  echo "apt:tor apt:hping3 apt:tcpflow apt:ngrep apt:python3-impacket pin:responder pin:netexec"
}

passwords_desc() { echo "Password cracking and wordlists: john, hashcat, hydra, medusa, SecLists"; }
passwords_items() {
  echo "apt:john apt:hashcat apt:pocl-opencl-icd apt:hydra apt:medusa apt:ncrack apt:crunch apt:cewl apt:hashid pin:seclists"
}

wireless_desc() { echo "Wi-Fi and Bluetooth: aircrack-ng, Kismet, reaver, wifite, hcxtools"; }
wireless_items() {
  echo "apt:aircrack-ng apt:wifite apt:reaver apt:bully apt:mdk4 apt:hcxtools apt:pixiewps apt:cowpatty apt:macchanger apt:wavemon apt:iw"
  echo "apt:btscanner apt:ubertooth pin:kismet"
}

exploit_desc() { echo "Exploitation: Metasploit Framework, searchsploit (Exploit-DB), pwntools"; }
exploit_items() { echo "pin:metasploit pin:exploitdb apt:sploitscan apt:python3-pwntools"; }

ad_desc() { echo "Active Directory: NetExec, Impacket, BloodHound CE, Certipy, kerbrute, evil-winrm"; }
ad_items() {
  echo "apt:python3-impacket apt:smbclient apt:smbmap apt:ldap-utils pin:netexec pin:kerbrute pin:evil-winrm pin:certipy"
  echo "pin:bloodhound-py pin:bloodhound-cli"
}

re_desc() { echo "Reverse engineering: Ghidra, radare2, binwalk, gdb with GEF"; }
re_items() {
  echo "apt:gdb apt:checksec apt:ltrace apt:strace apt:binwalk apt:upx-ucl apt:qemu-user pin:ghidra pin:radare2 pin:gef"
}

forensics_desc() { echo "Forensics: Sleuth Kit, Autopsy, Volatility 3, foremost, testdisk, yara"; }
forensics_items() {
  echo "apt:sleuthkit apt:autopsy apt:foremost apt:testdisk apt:guymager apt:yara apt:python3-yara apt:libimage-exiftool-perl pin:volatility3"
}

mobile_desc() { echo "Mobile apps: apktool, jadx, adb, Frida, objection"; }
mobile_items() { echo "apt:apktool apt:adb apt:apksigner pin:jadx pin:frida-tools pin:objection"; }

cloud_desc() { echo "Cloud and container security: Trivy, Prowler, ScoutSuite"; }
cloud_items() { echo "pin:trivy pin:prowler pin:scoutsuite"; }

osint_desc() { echo "Open-source intelligence: theHarvester, Sherlock, Maigret, recon-ng, exiftool"; }
osint_items() { echo "apt:sherlock apt:recon-ng apt:libimage-exiftool-perl apt:cutycapt pin:maigret pin:theharvester"; }

defense_desc() { echo "Defensive tools: lynis, rkhunter, chkrootkit, ClamAV, Suricata, yara, fail2ban, auditd, aide"; }
defense_items() {
  echo "apt:lynis apt:rkhunter apt:chkrootkit apt:clamav apt:suricata apt:yara apt:fail2ban apt:auditd apt:aide apt:lnav"
}
