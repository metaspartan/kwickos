#!/bin/bash
set -euo pipefail
export LC_ALL=C.UTF-8
DEST=${1:?destdir}
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/kwin-plugin.sh"
VER=${PLASMA_KEYBOARD_VERSION:-6.6.0}
SUM=${PLASMA_KEYBOARD_SHA256:-cc2ee9154e55e1a49c934aa8b2d4146a7209859de58057d96d297561652b76dc}
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends ca-certificates curl xz-utils patch binutils $KWIN_PLUGIN_DEPS \
  qt6-virtualkeyboard-dev qt6-wayland-dev qt6-wayland-private-dev qt6-wayland-dev-tools qt6-declarative-private-dev libkf6i18n-dev wayland-protocols gettext
S=$(mktemp -d)
curl -fsSL "https://download.kde.org/stable/plasma/$VER/plasma-keyboard-$VER.tar.xz" -o "$S/src.tar.xz"
echo "$SUM  $S/src.tar.xz" | sha256sum -c - >/dev/null
mkdir "$S/src" && tar -xJf "$S/src.tar.xz" -C "$S/src" --strip-components=1
sed -i -e 's/^set(QT_MIN_VERSION .*/set(QT_MIN_VERSION "6.8.0")/' -e 's/^set(KF6_MIN_VERSION .*/set(KF6_MIN_VERSION "6.13.0")/' \
  -e '/^add_subdirectory(kcm)$/d' -e '/^    KCMUtils$/d' -e '/^ki18n_install(po)$/d' "$S/src/CMakeLists.txt"
patch -s -d "$S/src" -p1 <<'PATCH'
--- a/src/qmlplugin/BreezeConstants.qml
+++ b/src/qmlplugin/BreezeConstants.qml
@@ -12,24 +12,26 @@
     property real scaleHint
 
     readonly property string fontFamily: Kirigami.Theme.defaultFont.family
-    readonly property real keyBackgroundMargin: Math.round(8 * scaleHint)
+    readonly property real keyBackgroundMargin: Math.round(7 * scaleHint)
     readonly property real keyContentMargin: Math.round(40 * scaleHint)
     readonly property real keyIconScale: scaleHint * 0.8
 
-    property color primaryColor: Kirigami.Theme.backgroundColor
+    readonly property bool dark: Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor) === Kirigami.ColorUtils.Dark
+    property color primaryColor: dark ? "#232325" : "#d1d3d9"
     property color primaryLightColor: Qt.lighter(primaryColor, 1.3)
     property color primaryDarkColor: Qt.darker(primaryColor, 1.3)
-    property color textOnPrimaryColor: Kirigami.Theme.textColor
-    property color secondaryColor: Kirigami.Theme.backgroundColor
+    property color textOnPrimaryColor: dark ? "#ffffff" : "#000000"
+    property color secondaryColor: dark ? "#636367" : "#ffffff"
     property color secondaryLightColor: Qt.lighter(secondaryColor, 1.3)
     property color secondaryDarkColor: Qt.darker(secondaryColor, 1.3)
-    property color textOnSecondaryColor: Kirigami.Theme.textColor
+    property color textOnSecondaryColor: textOnPrimaryColor
 
     property color keyboardBackgroundColor: primaryColor
-    property color normalKeyBackgroundColor: primaryLightColor
-    property color normalKeyPressedBackgroundColor: primaryDarkColor
-    property color highlightedKeyBackgroundColor: primaryLightColor
-    property color capsLockKeyAccentColor: secondaryColor
+    property color normalKeyBackgroundColor: dark ? "#5d5d61" : "#ffffff"
+    property color functionKeyBackgroundColor: dark ? "#3a3a3d" : "#abb0ba"
+    property color normalKeyPressedBackgroundColor: dark ? "#7d7d82" : "#abb0ba"
+    property color highlightedKeyBackgroundColor: functionKeyBackgroundColor
+    property color capsLockKeyAccentColor: textOnPrimaryColor
     property color modeKeyAccentColor: textOnPrimaryColor
     property color keyTextColor: textOnPrimaryColor
     property color keySmallTextColor: textOnPrimaryColor
@@ -45,6 +47,6 @@
     property color navigationHighlightColor: Qt.rgba(navigationHighlightBorderColor.r, navigationHighlightBorderColor.g, navigationHighlightBorderColor.b, 0.3)
     property color navigationHighlightBorderColor: Kirigami.Theme.highlightColor

-    readonly property real buttonRadius: Kirigami.Units.cornerRadius
-    readonly property real popupRadius: Kirigami.Units.cornerRadius
+    readonly property real buttonRadius: Math.round(16 * scaleHint)
+    readonly property real popupRadius: Math.round(20 * scaleHint)
 }
--- a/src/qmlplugin/BreezeKeyPanel.qml
+++ b/src/qmlplugin/BreezeKeyPanel.qml
@@ -22,11 +22,11 @@

     property color color: {
         if (control && control.pressed) {
-            return BreezeConstants.normalKeyPressedBackgroundColor;
+            return control.functionKey ? BreezeConstants.normalKeyBackgroundColor : BreezeConstants.normalKeyPressedBackgroundColor;
         } else if (control && control.highlighted) {
-            return BreezeConstants.highlightedKeyBackgroundColor;
+            return control.functionKey ? BreezeConstants.highlightedKeyBackgroundColor : BreezeConstants.normalKeyBackgroundColor;
         }
-        return BreezeConstants.normalKeyBackgroundColor;
+        return control && control.functionKey ? BreezeConstants.functionKeyBackgroundColor : BreezeConstants.normalKeyBackgroundColor;
     }

     soundEffect: PlasmaKeyboardSettings.soundEnabled ? Qt.resolvedUrl('qrc:///sounds/keyboard_tick2_quiet.wav') : ''
@@ -41,8 +41,8 @@
             radius: root.radius

             // Shadow
-            shadow.color: Qt.rgba(0, 0, 0, 0.2)
-            shadow.size: 3
+            shadow.color: Qt.rgba(0, 0, 0, BreezeConstants.dark ? 0.45 : 0.3)
+            shadow.size: 1
             shadow.yOffset: 1
         }
     }
PATCH
ICONS=/usr/share/plasma/keyboard/icons
STYLE=$S/src/src/styles/breeze/style.qml
sed -i "s/^        Qt::InputMethodHints qtHints;$/        Qt::InputMethodHints qtHints = Qt::ImhNoPredictiveText;/" "$S/src/src/inputlisteneritem.cpp"
grep -q "qtHints = Qt::ImhNoPredictiveText" "$S/src/src/inputlisteneritem.cpp"
for n in keyboard-caps-disabled-symbolic keyboard-caps-enabled-symbolic keyboard-caps-locked-symbolic keyboard-enter-symbolic edit-clear-symbolic globe globe-symbolic input-keyboard-virtual-hide-symbolic; do
  sed -i "s|\"$n\"|\"file://$ICONS/$n.svg\"|g" "$STYLE"
done
sed -i 's|^\( *\)Kirigami.Icon {$|&\n\1    isMask: true\n\1    color: theme.keyTextColor|' "$STYLE"
kwin_plugin_build "$S/src" "$DEST"
rm -rf "$S" "$DEST/usr/share/metainfo" "$DEST/usr/share/locale"
mkdir -p "$DEST$ICONS"
icon() {
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">%s</svg>\n' "$2" > "$DEST$ICONS/$1.svg"
}
SHIFT='M12 3.5 3.8 11.8H8v7.2h8v-7.2h4.2z'
icon keyboard-caps-disabled-symbolic "<path d=\"$SHIFT\"/>"
icon keyboard-caps-enabled-symbolic "<path d=\"$SHIFT\" fill=\"#000\"/>"
icon keyboard-caps-locked-symbolic '<path d="M12 3 3.8 11H8v5h8v-5h4.2z" fill="#000"/><path d="M8 20h8"/>'
icon edit-clear-symbolic '<path d="M8.6 5H19a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H8.6L2.8 12z"/><path d="m11.5 9.3 5.4 5.4m0-5.4-5.4 5.4"/>'
icon keyboard-enter-symbolic '<path d="M19.5 5v6.5a2.5 2.5 0 0 1-2.5 2.5H5"/><path d="m9 10-4 4 4 4"/>'
icon input-keyboard-virtual-hide-symbolic '<rect x="2.5" y="3" width="19" height="12" rx="2.2"/><path d="M6 7h.01M9.3 7h.01M12.6 7h.01M15.9 7h.01M7.5 11h9"/><path d="m9 18.5 3 2.5 3-2.5"/>'
icon globe '<circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3 12h18M4.6 7.5h14.8M4.6 16.5h14.8"/>'
cp "$DEST$ICONS/globe.svg" "$DEST$ICONS/globe-symbolic.svg"
find "$DEST/usr" -type f \( -name '*.so' -o -path '*/bin/*' \) -exec strip --strip-unneeded {} +
kwin_plugin_copyright "$DEST" plasma-keyboard <<EOF
plasma-keyboard $VER (KDE on-screen keyboard), built for KwickOS

Source: https://download.kde.org/stable/plasma/$VER/plasma-keyboard-$VER.tar.xz
sha256: $SUM
KwickOS changes: minimum Qt/KF versions lowered for Debian 13, the KCM and
translations are not built, typing commits every key (no word prediction),
key colours, radii and key glyphs follow the KwickOS
look in light and dark.

License: GPL-2.0-only OR GPL-3.0-only, LGPL-2.1-only OR LGPL-3.0-only for the
QML library, BSD-2-Clause for build files. License texts are in
/usr/share/common-licenses.
EOF
du -sh "$DEST/usr"
