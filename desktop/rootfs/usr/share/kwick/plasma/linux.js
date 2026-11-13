// KwickOS Linux (Zorin/GNOME-like) layout — applied by kwick-layout.
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

// Top panel: launcher, workspaces, centered clock, tray
var top = new Panel;
top.location = "top";
top.height = Math.round(gridUnit * 1.7);
top.floating = false;
top.hiding = "none";
top.opacity = "adaptive";

var k = top.addWidget("org.kde.plasma.kickoff");
k.currentConfigGroup = ["General"];
k.writeConfig("icon", "kwick-start");

top.addWidget("org.kde.plasma.pager");
top.addWidget("org.kde.plasma.panelspacer");

// Centered clock: date above, time below (GNOME style)
var clk = top.addWidget("org.kde.plasma.digitalclock");
clk.currentConfigGroup = ["Appearance"];
clk.writeConfig("showDate", "true");
clk.writeConfig("dateFormat", "custom");
clk.writeConfig("customDateFormat", "ddd d MMM");
clk.writeConfig("dateDisplayFormat", "BelowTime");
clk.writeConfig("use24hFormat", "false");
clk.writeConfig("showSeconds", "false");
clk.writeConfig("fontFamily", "Inter");
clk.writeConfig("fontWeight", "500");

top.addWidget("org.kde.plasma.panelspacer");
top.addWidget("org.kde.plasma.systemtray");

// Floating dock on the left
var dock = new Panel;
dock.location = "left";
dock.height = Math.round(gridUnit * 3.4);
dock.alignment = "center";
dock.lengthMode = "fit";
dock.floating = true;
dock.hiding = "dodgewindows";
dock.opacity = "adaptive";
var t = dock.addWidget("org.kde.plasma.icontasks");
t.currentConfigGroup = ["General"];
t.writeConfig("launchers", launchers);
t.writeConfig("showOnlyCurrentDesktop", "false");
