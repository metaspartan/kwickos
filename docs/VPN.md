# VPN on KwickOS

KwickOS has WireGuard in the kernel, NetworkManager VPN plugins on the desktop, a `kwick-vpn` command on both editions, and a
VPN page in KwickOS Settings.

## Kernel

| Flavor | What is enabled |
|---|---|
| `virt` (module-free, microVMs and cloud) | WireGuard and TUN built in (OpenVPN, wg-quick, Tailscale, NetBird, ZeroTier work). No IPsec, L2TP or PPP, to keep the image small. |
| `generic` (desktop and bare metal) | The same, plus modules for IPsec (`xfrm_user`, `xfrm_interface`, `af_key`, ESP, AH, IPComp for IPv4 and IPv6), GRE, IPIP and SIT tunnels, L2TP (v2 and v3, `l2tp_ppp`, `l2tp_ip`, `l2tp_eth`), PPP (async, sync tty, deflate, BSD compress, MPPE, PPPoE, PPTP) and the crypto they need (AEAD and GCM, CTR, CMAC, XCBC, HMAC, MD5, SHA1, SHA512, DES, ARC4, deflate). Modules load on demand. |

WireGuard and TUN were already built in through `config/kernel/common.config`; the new options are in
`config/kernel/generic.config`.

## Desktop packages

Installed with the desktop (`desktop/packages.list`): `wireguard-tools`, `openvpn`, `openconnect`,
`network-manager-openvpn`, `network-manager-openconnect` (Cisco AnyConnect, GlobalProtect, Fortinet, Pulse, Juniper),
`network-manager-vpnc`, `network-manager-l2tp`, `network-manager-strongswan`, `network-manager-sstp` and the `-gnome` editors for
OpenVPN, vpnc, L2TP and SSTP. Installed size: about 33 MB for the plugins and tools plus 1.3 MB for the GNOME editors, measured
with `apt-get install --no-install-recommends` on top of `network-manager plasma-nm gnome-shell gnome-control-center` in a
Debian 13 container.

Notes:

* `plasma-nm` ships its own WireGuard and OpenVPN editors, so Plasma needs nothing else.
* `network-manager-fortisslvpn` is not in Debian 13. Fortinet works through `network-manager-openconnect` (protocol Fortinet).
* `network-manager-openconnect-gnome` is left out on purpose: it pulls in WebKitGTK (about 180 MB). On GNOME, create OpenConnect
  profiles with `nmcli` or from the Plasma editor, or install it with `apt install network-manager-openconnect-gnome`.
* `network-manager-pptp` is not installed, since PPTP is broken cryptographically.

## In each session

* Plasma: the network applet in the system tray lists VPN connections with a connect button, in the macOS, Windows and Linux
  layouts alike. The tray uses its default items, so nothing hides it.
* GNOME: the VPN toggle appears in quick settings as soon as a profile exists. Nothing in the KwickOS GNOME settings hides it.
* Hyprland and sway: waybar has a `custom/vpn` module that shows a lock while a NetworkManager VPN, a WireGuard interface or a
  provider tunnel (Tailscale, Mullvad, Proton, ZeroTier, NetBird) is up, and hides itself otherwise. Click it to open `nmtui`.
  The module runs `kwick-vpn waybar`.

## kwick-vpn

```sh
kwick-vpn import office.conf        # WireGuard (.conf with [Interface]) or OpenVPN (.ovpn / .conf)
kwick-vpn list                      # name, type, up or down
kwick-vpn up office
kwick-vpn down office
kwick-vpn status                    # active VPNs, exit status 1 when none
kwick-vpn providers                 # optional providers and whether they are installed
kwick-vpn install base              # headless: wireguard-tools, openvpn (and openresolv when nothing provides resolvconf)
kwick-vpn install plugins           # NetworkManager VPN plugins on a system that lacks them
kwick-vpn install tailscale         # or mullvad, protonvpn, protonvpn-cli, zerotier, netbird
```

With NetworkManager running, `import` calls `nmcli connection import type wireguard|openvpn` (WireGuard profile names are
shortened to the 15 character interface limit) and `up` and `down` use `nmcli connection`. Without it, profiles are stored in
`/etc/wireguard` and `/etc/openvpn/client` and driven by `wg-quick` and `openvpn` (the `openvpn-client@name` unit under systemd, a
daemon with a pid file otherwise). Commands that need root use `sudo` or `pkexec`.

### Providers

Providers are never preinstalled. `kwick-vpn install` adds the vendor apt repository, checks that the downloaded signing key
has exactly the pinned primary fingerprint, installs it to `/usr/share/keyrings` and uses `signed-by`, then installs the package.

| Provider | Repository | Key fingerprint | Architectures |
|---|---|---|---|
| Tailscale | `pkgs.tailscale.com/stable/debian trixie` | `2596A99EAAB33821893C0A79458CA832957F5868` | amd64, arm64, riscv64 |
| Mullvad | `repository.mullvad.net/deb/stable` | `A1198702FC3E0A09A9AE5B75D5A1D4F266DE8DDF` | amd64, arm64 |
| Proton VPN | `repo.protonvpn.com/debian stable` | `84B0D3492C76C9C6F5873C18EDA3E22630349F1C` | amd64, arm64 |
| ZeroTier | `download.zerotier.com/debian/trixie` | `74A5E9C458E1A431F1DA57A71657198823E52A61` | amd64, arm64 |
| NetBird | `pkgs.netbird.io/debian stable` | `EFE37DF047DF7CCDF1FC54FA83F79AD029778355` | amd64, arm64 |

`protonvpn` installs the graphical app (`proton-vpn-gnome-desktop`); `protonvpn-cli` installs `proton-vpn-cli`. After installing,
Tailscale needs `sudo tailscale up`, NetBird `sudo netbird up` and ZeroTier `sudo zerotier-cli join <network>`.

## Settings

KwickOS Settings, VPN: the connection list with an on and off toggle for each VPN and WireGuard profile, Import configuration
(file dialog, then `kwick-vpn import`), a shortcut to the network editor, and install rows for the five providers with their state.
