var dockCfg = {
    position: "bottom",
    iconSize: 48,
    autohide: "off",
    floating: "on",
    pinned: "org.kde.dolphin.desktop,firefox-esr.desktop,org.kde.konsole.desktop,org.kde.kate.desktop,org.kde.discover.desktop,kwick-settings.desktop"
};
if (typeof KWICK_DOCK !== "undefined") {
    for (var key in KWICK_DOCK) { dockCfg[key] = KWICK_DOCK[key]; }
}

var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    var d = desktopsArray[j];
    d.wallpaperPlugin = "org.kde.image";
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    d.writeConfig("Image", "file:///usr/share/wallpapers/KwickGlass/contents/images/2560x1440.png");
    d.writeConfig("FillMode", "2");
}
panels().forEach(function (p) { p.remove(); });

var launchers = dockCfg.pinned.split(",").filter(function (s) { return s.length > 0; })
    .map(function (s) { return "applications:" + s; }).join(",");

var top = new Panel;
top.location = "top";
top.height = Math.round(gridUnit * 1.6);
top.floating = false;
top.hiding = "none";
top.opacity = "translucent";
top.alignment = "left";
top.lengthMode = "fill";

var edgeL = top.addWidget("org.kde.plasma.marginsseparator");
edgeL.currentConfigGroup = ["General"];
edgeL.writeConfig("margin", "10");

var k = top.addWidget("org.kde.plasma.kickoff");
k.currentConfigGroup = ["General"];
k.writeConfig("icon", "kwickos-symbolic");
k.writeConfig("showAppsByName", "true");

var gapL = top.addWidget("org.kde.plasma.marginsseparator");
gapL.currentConfigGroup = ["General"];
gapL.writeConfig("margin", "6");

top.addWidget("org.kde.plasma.appmenu");
top.addWidget("org.kde.plasma.panelspacer");

var sep1 = top.addWidget("org.kde.plasma.marginsseparator");
sep1.currentConfigGroup = ["General"];
sep1.writeConfig("margin", "8");
top.addWidget("org.kde.plasma.systemtray");
var sep3 = top.addWidget("org.kde.plasma.marginsseparator");
sep3.currentConfigGroup = ["General"];
sep3.writeConfig("margin", "6");

var clk = top.addWidget("org.kde.plasma.digitalclock");
clk.currentConfigGroup = ["Appearance"];
clk.writeConfig("showDate", "true");
clk.writeConfig("dateFormat", "custom");
clk.writeConfig("customDateFormat", "ddd MMM d");
clk.writeConfig("dateDisplayFormat", "BesideTime");
clk.writeConfig("use24hFormat", 0);
clk.writeConfig("showSeconds", "false");
clk.writeConfig("fontFamily", "Inter");
clk.writeConfig("fontWeight", "500");
clk.writeConfig("fontSize", "9");
clk.writeConfig("autoFontAndSize", "false");

var sep2 = top.addWidget("org.kde.plasma.marginsseparator");
sep2.currentConfigGroup = ["General"];
sep2.writeConfig("margin", "8");

var dock = new Panel;
dock.location = dockCfg.position;
dock.height = parseInt(dockCfg.iconSize, 10) + 20;
dock.alignment = "center";
dock.lengthMode = "fit";
dock.floating = dockCfg.floating !== "off";
dock.hiding = dockCfg.autohide === "on" ? "autohide" : "dodgewindows";
dock.opacity = "translucent";

var dl = dock.addWidget("org.kde.plasma.marginsseparator");
dl.currentConfigGroup = ["General"];
dl.writeConfig("margin", "4");
var t = dock.addWidget("org.kde.plasma.icontasks");
t.currentConfigGroup = ["General"];
t.writeConfig("launchers", launchers);
t.writeConfig("showOnlyCurrentDesktop", "false");
t.writeConfig("iconSpacing", "2");
t.writeConfig("indicateAudioStreams", "true");
t.writeConfig("showToolTips", "true");
t.writeConfig("groupingStrategy", "0");
t.writeConfig("middleClickAction", "None");
t.writeConfig("maxStripes", "1");
var dm = dock.addWidget("org.kde.plasma.marginsseparator");
dm.currentConfigGroup = ["General"];
dm.writeConfig("margin", "8");
dock.addWidget("org.kde.plasma.trash");
var dr = dock.addWidget("org.kde.plasma.marginsseparator");
dr.currentConfigGroup = ["General"];
dr.writeConfig("margin", "4");
