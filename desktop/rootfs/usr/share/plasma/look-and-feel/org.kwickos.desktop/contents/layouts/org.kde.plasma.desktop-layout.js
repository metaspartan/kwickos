// KwickOS macOS (liquid glass) layout. Applied by kwick-layout and (macOS flavour) as the first-login default.
var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    var d = desktopsArray[j];
    d.wallpaperPlugin = "org.kde.image";
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    d.writeConfig("Image", "file:///usr/share/wallpapers/KwickGlass/contents/images/2560x1440.png");
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
// translucent menu bar: launcher, global menu, tray, clock
var top = new Panel;
top.location = "top"; top.height = Math.round(gridUnit * 1.5); top.floating = false; top.hiding = "none"; top.opacity = "translucent";
var k = top.addWidget("org.kde.plasma.kickoff");
k.currentConfigGroup = ["General"]; k.writeConfig("icon", "kwick-start");
top.addWidget("org.kde.plasma.appmenu");
top.addWidget("org.kde.plasma.panelspacer");
top.addWidget("org.kde.plasma.systemtray");
clockCfg(top.addWidget("org.kde.plasma.digitalclock"), "ddd d MMM", false);

// floating glass dock
var dock = new Panel;
dock.location = "bottom"; dock.height = Math.round(gridUnit * 3.6); dock.alignment = "center"; dock.lengthMode = "fit";
dock.floating = true; dock.hiding = "dodgewindows"; dock.opacity = "translucent";
var t = dock.addWidget("org.kde.plasma.icontasks");
t.currentConfigGroup = ["General"]; t.writeConfig("launchers", launchers); t.writeConfig("showOnlyCurrentDesktop", "false");
t.writeConfig("iconSpacing", "3"); t.writeConfig("indicateAudioStreams", "true");
dock.addWidget("org.kde.plasma.marginsseparator");
dock.addWidget("org.kde.plasma.trash");