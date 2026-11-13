// KwickOS Windows 11 layout. Applied by kwick-layout and (macOS flavour) as the first-login default.
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
function clockCfg(c, fmt, below) {
    c.currentConfigGroup = ["Appearance"];
    c.writeConfig("showDate", "true");
    c.writeConfig("dateFormat", "custom");
    c.writeConfig("customDateFormat", fmt);
    c.writeConfig("dateDisplayFormat", below ? "BelowTime" : "BesideTime");
}
// Windows 11: centered icons on a translucent full-width taskbar; tray + clock on the right.
var p = new Panel;
p.location = "bottom"; p.height = Math.round(gridUnit * 2.9); p.floating = false; p.hiding = "none"; p.opacity = "translucent";
var lead = p.addWidget("org.kde.plasma.panelspacer");          // fixed spacer mirrors the tray width so the icons stay centered
lead.currentConfigGroup = ["Configuration", "General"]; lead.writeConfig("expanding", "false"); lead.writeConfig("length", "230");
var l2 = p.addWidget("org.kde.plasma.panelspacer");
var k = p.addWidget("org.kde.plasma.kickoff");
k.currentConfigGroup = ["General"]; k.writeConfig("icon", "kwick-start-fluent");
var t = p.addWidget("org.kde.plasma.icontasks");
t.currentConfigGroup = ["General"]; t.writeConfig("launchers", launchers); t.writeConfig("showOnlyCurrentDesktop", "false");
t.writeConfig("iconSpacing", "2"); t.writeConfig("maxStripes", "1");
p.addWidget("org.kde.plasma.panelspacer");
p.addWidget("org.kde.plasma.systemtray");
var c = p.addWidget("org.kde.plasma.digitalclock");
clockCfg(c, "M/d/yyyy", true);
c.writeConfig("use24hFormat", "1");
p.addWidget("org.kde.plasma.showdesktop");