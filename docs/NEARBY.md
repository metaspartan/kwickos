# Send Nearby

Send Nearby sends files and text between KwickOS and the phones and computers around it. It speaks the open
[LocalSend protocol v2](https://github.com/localsend/protocol), so it works with the LocalSend app on Android, iPhone,
Windows, macOS and Linux, and between KwickOS computers. Nothing has to be set up and no account is involved.

## Using it

* **Send**: right-click files in Files (Dolphin or Nautilus) and choose **Send Nearby…**, press the share button in
  Glance's toolbar or on Capture's screenshot thumbnail, or open **Send Nearby** from the launcher or Search
  to type a message or choose files. The sheet lists the devices it finds; click one to send. Click it again to stop.
  A device that asks for a PIN gets a PIN field.
* **Receive**: choose who can find you under *Allow me to be discovered by* (in the sheet, in Settings › Send Nearby
  or in Quick Settings on KDE):
  * **Receiving Off** (default): nothing listens; you can still send.
  * **Known Devices Only**: only devices you accepted something from before can find you and ask.
  * **Everyone for 10 Minutes**: any device on the network can ask; then it falls back to Known Devices Only.

  Every incoming transfer shows a prompt with the sender, the device and the files; nothing is saved before you click
  **Accept**. Files go to `~/Downloads` (configurable); text and links can be copied or opened.

## Network and firewall

| Port | Protocol | Use |
| --- | --- | --- |
| 53317 | UDP | multicast discovery on 224.0.0.167 |
| 53317 | TCP | HTTPS server (TLS 1.2 or newer) for register, prepare-upload, upload, cancel |

Allow both to receive. Sending needs only outgoing connections plus the UDP replies. When multicast is filtered (some
Wi-Fi access points do this), the sheet scans the local /24 over HTTPS after a few seconds, like LocalSend does.

`kwick-nearby --status` prints the settings as JSON, `kwick-nearby --set visibility everyone|contacts|off`,
`--set alias NAME`, `--set folder DIR` and `--set pin 1234` change them.

## Security

* Runs as the user, no root, no system service. The receiver runs only while receiving is on (or the share sheet is
  open), started per session from XDG autostart (KDE, GNOME) or `exec-once` (Hyprland, sway).
* Each user has a self-signed RSA-2048 certificate in `~/.local/share/kwick/nearby/` (key mode 0600). Its SHA-256
  fingerprint is the device identity, as in LocalSend. When sending, the receiver's certificate must match the
  fingerprint it announced, otherwise the transfer fails with *Certificate mismatch*. A known device is only ever sent
  to over HTTPS; one that announces `"protocol":"http"` fails with *Not verified*.
* Fingerprints are broadcast in the clear, so a fingerprint in a JSON body or announcement proves nothing. A device is
  marked known only after its own certificate was checked: its server certificate when Send Nearby connects to it
  over HTTPS, or the TLS client certificate it presents when it connects. Devices seen only through an announcement,
  or over plain HTTP, are listed as new devices. An unverified announcement never changes a verified entry: from the
  same address it only keeps the device alive (the alias and model change after the device re-registers over HTTPS), and
  from another address it is ignored.
* **Known Devices Only** accepts a request only when the sender's TLS client certificate matches a known device.
  Senders without a client certificate get `403` with *Known devices only: the sender presented no TLS client
  certificate*, unknown certificates get `403` with *Known devices only: the sender's certificate is not a known
  device*. A sender is remembered after **Accept** only when it presented a client certificate, so LocalSend apps
  that don't present one can send in **Everyone** mode but never become known devices.
* Uploads are accepted only with the per-file token from an accepted session and only from the sender's address.
  File names are reduced to safe relative paths inside the receive folder (no `..`, no absolute paths, no hidden
  names), existing files are never overwritten, partial files are deleted on failure, and the free space is checked
  first. One session at a time; requests are refused while a prompt is open, and a prompt expires after 2 minutes.
* The optional PIN allows three wrong attempts per address before refusing further requests.

## Files

`src/kwick-nearby/` (C++/Qt Quick, shipped in the `kwick-native` part of `kwick-desktop`):
`server.cpp` (HTTPS server), `discovery.cpp` (multicast, register, subnet scan), `sender.cpp` (uploads),
`identity.cpp` (certificate), `nearby.cpp` (policy, windows), `qml/` (share sheet and prompt),
`nautilus/` (Nautilus menu extension). Settings: `desktop/rootfs/usr/share/kwick/settings/PageNearby.qml`;
Quick Settings: `NearbySource.qml` and `NearbyPage.qml` in `org.kwickos.controlcenter`.
