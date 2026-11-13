// KwickOS Windows 11 layout — applied by kwick-layout.
var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    var d = desktopsArray[j];
    d.wallpaperPlugin = "org.kde.image";
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    d.writeConfig("Image", "file:///usr/share/wallpapers/KwickFluent/contents/images/2560x1440.png");
    d.writeConfig("FillMode", "2");
}
panels().forEach(function (p) { p.remove(); });
var launchers = [
    "applications:org.kde.dolphin.desktop", "applications:firefox-esr.desktop",
    "applications:org.kde.konsole.desktop", "applications:org.kde.kate.desktop",
    "applications:org.kde.discover.desktop", "applications:steam.desktop",
    "applications:systemsettings.desktop"
].join(",");

// Windows 11: centered icons on a translucent full-width taskbar; tray + clock on the right.
var p = new Panel;
p.location = "bottom";
p.height = Math.round(gridUnit * 2.9);
p.floating = false;
p.hiding = "none";
p.opacity = "translucent";

// Left fixed spacer mirrors the tray+clock width so icons stay visually centered
var lead = p.addWidget("org.kde.plasma.panelspacer");
lead.currentConfigGroup = ["Configuration", "General"];
lead.writeConfig("expanding", "false");
lead.writeConfig("length", "260");

var l2 = p.addWidget("org.kde.plasma.panelspacer");

// Start button — original KwickOS mark (not the Windows logo)
var k = p.addWidget("org.kde.plasma.kickoff");
k.currentConfigGroup = ["General"];
k.writeConfig("icon", "kwick-start-fluent");

// Centered task icons
var t = p.addWidget("org.kde.plasma.icontasks");
t.currentConfigGroup = ["General"];
t.writeConfig("launchers", launchers);
t.writeConfig("showOnlyCurrentDesktop", "false");
t.writeConfig("iconSpacing", "2");
t.writeConfig("maxStripes", "1");

p.addWidget("org.kde.plasma.panelspacer");

// Tray + clock (right side, Windows 11 style)
p.addWidget("org.kde.plasma.systemtray");
var c = p.addWidget("org.kde.plasma.digitalclock");
c.currentConfigGroup = ["Appearance"];
c.writeConfig("showDate", "true");
c.writeConfig("dateFormat", "custom");
c.writeConfig("customDateFormat", "M/d/yyyy");
c.writeConfig("dateDisplayFormat", "BelowTime");
c.writeConfig("use24hFormat", 0);
c.writeConfig("showSeconds", "false");
c.writeConfig("fontFamily", "Inter");
c.writeConfig("fontWeight", "400");
c.writeConfig("fontSize", "8");           // Windows 11 clock is small
c.writeConfig("autoFontAndSize", "false");

var edge = p.addWidget("org.kde.plasma.marginsseparator");
edge.currentConfigGroup = ["General"];
edge.writeConfig("margin", "8");
p.addWidget("org.kde.plasma.showdesktop");
