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

* Plasma: the `org.kwickos.vpn` plasmoid
  (`desktop/rootfs/usr/share/plasma/plasmoids/org.kwickos.vpn`) is the VPN menu bar item, like macOS's VPN status menu. It is a
  system tray item (`X-Plasma-NotificationArea`, category Hardware, enabled by default), so every layout picks it up without
  layout script changes: in the macOS menu bar it sits right next to the network icon, in the Windows and Linux layouts it is in
  the system tray. It is hidden while no VPN profile exists and appears as soon as one is imported.
  * Glyph: white, 22 px, from the icon theme, in three states: `network-vpn-symbolic` (connected), `network-vpn-acquiring-symbolic`
    (connecting, and the glyph pulses) and `network-vpn-disconnected-symbolic`. See [Icons](#icons).
  * Popup: a row per VPN and WireGuard profile with a switch, the connect time and tunnel address for the connected one,
    Connecting… and Disconnecting… while NetworkManager works, and NetworkManager's failure reason in red when a connection
    does not come up (Timed out, Secrets were required, Login failed, The VPN service did not start, and so on).
    Below them, Import Configuration… (file dialog, then `kwick-vpn import`, result shown in the popup) and VPN Settings… (opens
    KwickOS Settings on the VPN page; the gear in the popup header and the right-click Configure entry do the same).
  * Live state comes from Plasma's own `org.kde.plasma.networkmanagement` QML module (the `NetworkModel` that plasma-nm
    uses), so nothing is polled while NetworkManager runs. A switch runs `kwick-vpn up` or `down` with the profile's UUID, which
    waits for NetworkManager and returns the failure reason; secrets are asked for by plasma-nm's agent as usual. Without
    NetworkManager the plasmoid falls back to `kwick-vpn list` through the executable data engine every 3 s.
  * plasma-nm stays in the tray as the full network menu and still lists VPNs among the other connections. Its icon does not get a
    lock badge while a VPN is up: the KwickOS themes draw `network-*-locked` the same as the plain network icon, so the VPN state is
    shown once, by the VPN item. While a VPN is connecting plasma-nm still spins its busy ring on the network icon.
* GNOME: the VPN toggle appears in quick settings as soon as a profile exists, and the top bar uses the same KwickOS VPN glyphs.
* Hyprland and sway: waybar's `custom/vpn` module runs `kwick-vpn waybar` every 5 s (and right after `kwick-vpn` changes
  anything, through signal 10). It shows the layout's VPN glyph with the class `connected`, `connecting` (pulsing) or
  `disconnected`, and hides itself when there are no profiles and no tunnel. Click it for a fuzzel menu of the profiles that toggles
  the one you pick (`kwick-vpn menu`, with a notification on success or failure); right-click opens VPN Settings.

## kwick-vpn

```sh
kwick-vpn import office.conf        # WireGuard (.conf with [Interface]) or OpenVPN (.ovpn / .conf)
kwick-vpn list                      # name, type, connected / connecting / disconnecting / disconnected, tunnel address
kwick-vpn up office
kwick-vpn down office
kwick-vpn toggle office
kwick-vpn status                    # connected VPNs and tunnels, exit status 1 when none
kwick-vpn menu                      # fuzzel menu of the profiles, toggles the one you pick
kwick-vpn waybar                    # {"text","alt","class","tooltip"} for waybar
kwick-vpn providers                 # VPN plugins and optional providers, and whether they are installed
kwick-vpn install base              # headless: wireguard-tools, openvpn (and openresolv when nothing provides resolvconf)
kwick-vpn install plugins           # NetworkManager VPN plugins on a system that lacks them
kwick-vpn install tailscale         # or mullvad, protonvpn, protonvpn-cli, zerotier, netbird
kwick-vpn install --progress mullvad   # same, with apt status lines (pmstatus/dlstatus) for a progress bar
```

`list` prints tab-separated rows sorted by name when piped and a table on a terminal. `import` checks the file before touching
anything: WireGuard needs `[Interface]` with `PrivateKey` and `Address` and a `[Peer]` with `PublicKey` and `AllowedIPs`, OpenVPN
needs a `remote` line or a `<connection>` block, and the name must not exist yet. Errors name the file and the missing part, for
example `noaddr.conf is not a valid WireGuard profile: the [Interface] section has no Address`.

With NetworkManager running, `import` calls `nmcli connection import type wireguard|openvpn` (WireGuard profile names are
shortened to the 15 character interface limit), turns autoconnect off and leaves the profile disconnected, like macOS does with
an imported configuration. It refuses OpenVPN files when `network-manager-openvpn` is missing and says to run `kwick-vpn install
plugins`. `up` and `down` use `nmcli connection` (by name or UUID) and report NetworkManager's activation failure reason, shortened
to Timed out, Secrets were required, Login failed, The VPN service did not start, The VPN server sent an invalid configuration,
The VPN service stopped unexpectedly or The network connection was interrupted, and NetworkManager's own text otherwise. When polkit refuses `nmcli` (a session
that is not the active one), the command is retried as root. Without NetworkManager, profiles are stored in `/etc/wireguard` and
`/etc/openvpn/client` and driven by `wg-quick` and `openvpn` (the `openvpn-client@name` unit under systemd, a daemon with a pid file
otherwise); their names are also recorded in `/var/lib/kwick-vpn/profiles` so `list` works without root, and a failing `wg-quick`
or `openvpn` makes `up` and `down` exit non-zero with its last line. Commands that need root use `sudo`, or `pkexec` when sudo
would ask for a password.

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

KwickOS Settings, VPN (`kwick-settings vpn` opens it directly):

* VPN Configurations: a row per profile with its state dot, Connected and the tunnel address, Connecting…, Disconnecting… or Not
  Connected, the profile type and a switch. The list refreshes every 2.5 s from `kwick-vpn list`. While a switch works the row
  pulses and the switch is disabled; when `kwick-vpn up` or `down` fails, the reason appears in red under the row.
* With no profiles the card shows an empty state that explains what to import, with Import Configuration… and Network Editor….
* Import Configuration… opens the native file dialog (Downloads first) and runs `kwick-vpn import`; the result or the validation
  error appears under Add a VPN.
* Providers: NetworkManager VPN plugins and the five providers with their state. Install runs `kwick-vpn install --progress`
  as root (sudo when it needs no password, pkexec otherwise) in the background, shows apt's current step and a progress bar
  (indeterminate until apt reports a percentage) and, if it fails, apt's error in red with Try Again.

## Icons

The VPN glyphs are generated with the other tray glyphs and filled for GTK by `tools/icons/fill-symbolic.py`:

| layout | theme | connected | connecting | disconnected |
|---|---|---|---|---|
| macOS | `KwickOS` (`gen-tray.py`) | solid VPN badge with the letters cut out | the same badge at 55% | outlined badge |
| Windows | `KwickOS-Fluent` (`gen-icons.py`) | solid shield with the key cut out | outlined shield, faded key | outlined shield with key |
| Linux | `KwickOS-Linux` (`gen-icons.py`) | solid padlock with the keyhole cut out | padlock with three dots | open padlock |

Names: `network-vpn`, `network-vpn-acquiring`, `network-vpn-disconnected` (also `-disabled` and `-offline`), each with
`-symbolic`. `fill-symbolic.py` subtracts every shape painted with its `CUT` colour (`#ff00ff`) from the rest, which is how the
letters, key and keyhole are knocked out; it converts any SVG that uses that colour, not only `-symbolic` ones. The VPN letters
are drawn on whole pixels with 1 px stems so they stay sharp at 22 px. After regenerating, the image build refreshes the GTK icon
caches (`gtk-update-icon-cache -f -t` for the three themes and hicolor in `desktop/Dockerfile`).
