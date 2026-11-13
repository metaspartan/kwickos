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

var top = new Panel;
top.location = "top";
top.height = Math.round(gridUnit * 1.5);
top.floating = false;
top.hiding = "none";
top.opacity = "translucent";

var edgeL = top.addWidget("org.kde.plasma.marginsseparator");
edgeL.currentConfigGroup = ["General"];
edgeL.writeConfig("margin", "8");
var k = top.addWidget("org.kde.plasma.kickoff");
k.currentConfigGroup = ["General"];
k.writeConfig("icon", "kwick-start");
var gapL = top.addWidget("org.kde.plasma.marginsseparator");
gapL.currentConfigGroup = ["General"];
gapL.writeConfig("margin", "10");

top.addWidget("org.kde.plasma.panelspacer");

var clk = top.addWidget("org.kde.plasma.digitalclock");
clk.currentConfigGroup = ["Appearance"];
clk.writeConfig("showDate", "true");
clk.writeConfig("dateFormat", "custom");
clk.writeConfig("customDateFormat", "ddd d MMM");
clk.writeConfig("dateDisplayFormat", "BesideTime");
clk.writeConfig("use24hFormat", 0);
clk.writeConfig("showSeconds", "false");
clk.writeConfig("fontFamily", "Ubuntu Sans");
clk.writeConfig("fontWeight", "500");
clk.writeConfig("fontSize", "9");
clk.writeConfig("autoFontAndSize", "false");

top.addWidget("org.kde.plasma.panelspacer");
var sepT = top.addWidget("org.kde.plasma.marginsseparator");
sepT.currentConfigGroup = ["General"];
sepT.writeConfig("margin", "6");
top.addWidget("org.kde.plasma.systemtray");
var edgeR = top.addWidget("org.kde.plasma.marginsseparator");
edgeR.currentConfigGroup = ["General"];
edgeR.writeConfig("margin", "8");

var dock = new Panel;
dock.location = "left";
dock.height = 60;
dock.alignment = "center";
dock.lengthMode = "fit";
dock.floating = true;
dock.hiding = "dodgewindows";
dock.opacity = "translucent";
var dv = dock.addWidget("org.kde.plasma.marginsseparator");
dv.currentConfigGroup = ["General"];
dv.writeConfig("margin", "4");
var t = dock.addWidget("org.kde.plasma.icontasks");
t.currentConfigGroup = ["General"];
t.writeConfig("launchers", launchers);
t.writeConfig("showOnlyCurrentDesktop", "false");
t.writeConfig("iconSpacing", "2");
t.writeConfig("maxStripes", "1");
var dw = dock.addWidget("org.kde.plasma.marginsseparator");
dw.currentConfigGroup = ["General"];
dw.writeConfig("margin", "4");
