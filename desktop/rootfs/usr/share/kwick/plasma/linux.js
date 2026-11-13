// KwickOS Linux layout. Applied by kwick-layout and (macOS flavour) as the first-login default.
var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    var d = desktopsArray[j];
    d.wallpaperPlugin = "org.kde.image";
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    d.writeConfig("Image", "file:///usr/share/wallpapers/KwickOS/contents/images/2560x1440.png");
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
// Linux (Zorin/GNOME-like): top panel with workspaces and a floating dock on the left.
var top = new Panel;
top.location = "top"; top.height = Math.round(gridUnit * 1.7); top.floating = false; top.hiding = "none"; top.opacity = "adaptive";
var k = top.addWidget("org.kde.plasma.kickoff");
k.currentConfigGroup = ["General"]; k.writeConfig("icon", "kwick-start");
top.addWidget("org.kde.plasma.pager");
top.addWidget("org.kde.plasma.panelspacer");
clockCfg(top.addWidget("org.kde.plasma.digitalclock"), "ddd d MMM", false);
top.addWidget("org.kde.plasma.panelspacer");
top.addWidget("org.kde.plasma.systemtray");
var dock = new Panel;
dock.location = "left"; dock.height = Math.round(gridUnit * 3.4); dock.alignment = "center"; dock.lengthMode = "fit";
dock.floating = true; dock.hiding = "dodgewindows"; dock.opacity = "adaptive";
var t = dock.addWidget("org.kde.plasma.icontasks");
t.currentConfigGroup = ["General"]; t.writeConfig("launchers", launchers); t.writeConfig("showOnlyCurrentDesktop", "false");