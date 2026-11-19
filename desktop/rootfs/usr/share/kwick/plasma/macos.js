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
    d.writeConfig("Image", "file:///usr/share/wallpapers/" + (typeof KWICK_APPEARANCE !== "undefined" && KWICK_APPEARANCE === "light" ? "KwickGlassLight" : "KwickGlass") + "/contents/images/2560x1440.png");
    d.writeConfig("FillMode", "2");
}
panels().forEach(function (p) { p.remove(); });

var launchers = dockCfg.pinned.split(",").filter(function (s) { return s.length > 0; })
    .map(function (s) { return "applications:" + s; }).join(",");

var top = new Panel;
top.location = "top";
top.height = Math.round(gridUnit * 1.8);
top.floating = false;
top.hiding = "none";
top.opacity = "translucent";
top.alignment = "left";
top.lengthMode = "fill";

var edgeL = top.addWidget("org.kde.plasma.marginsseparator");
edgeL.currentConfigGroup = ["General"];
edgeL.writeConfig("margin", "10");

if (knownWidgetTypes.indexOf("org.kwickos.applemenu") >= 0) {
    top.addWidget("org.kwickos.applemenu");
} else {
    var k = top.addWidget("org.kde.plasma.kickoff");
    k.currentConfigGroup = ["General"];
    k.writeConfig("icon", "kwickos-menubar");
    k.writeConfig("showAppsByName", "true");
}

var gapL = top.addWidget("org.kde.plasma.marginsseparator");
gapL.currentConfigGroup = ["General"];
gapL.writeConfig("margin", "6");

top.addWidget("org.kde.plasma.appmenu");
top.addWidget("org.kde.plasma.panelspacer");

var sep1 = top.addWidget("org.kde.plasma.marginsseparator");
sep1.currentConfigGroup = ["General"];
sep1.writeConfig("margin", "8");
var tray = top.addWidget("org.kde.plasma.systemtray");
tray.currentConfigGroup = [];
var trayInner = desktopById(tray.readConfig("SystrayContainmentId"));
if (trayInner) {
    trayInner.currentConfigGroup = ["General"];
    trayInner.writeConfig("iconSpacing", "3");
}
var sep3 = top.addWidget("org.kde.plasma.marginsseparator");
sep3.currentConfigGroup = ["General"];
sep3.writeConfig("margin", "6");
if (knownWidgetTypes.indexOf("org.kwickos.spotlight") >= 0) {
    top.addWidget("org.kwickos.spotlight");
    var sep5 = top.addWidget("org.kde.plasma.marginsseparator");
    sep5.currentConfigGroup = ["General"];
    sep5.writeConfig("margin", "2");
}
if (knownWidgetTypes.indexOf("org.kwickos.controlcenter") >= 0) {
    if (trayInner) {
        trayInner.writeConfig("hiddenItems", ["org.kde.plasma.volume", "org.kde.plasma.brightness"]);
    }
    top.addWidget("org.kwickos.controlcenter");
    var sep4 = top.addWidget("org.kde.plasma.marginsseparator");
    sep4.currentConfigGroup = ["General"];
    sep4.writeConfig("margin", "6");
}

if (knownWidgetTypes.indexOf("org.kwickos.clock") >= 0) {
    top.addWidget("org.kwickos.clock");
} else {
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
}

var sep2 = top.addWidget("org.kde.plasma.marginsseparator");
sep2.currentConfigGroup = ["General"];
sep2.writeConfig("margin", "12");

var dock = new Panel;
dock.location = dockCfg.position;
dock.height = parseInt(dockCfg.iconSize, 10) + 24;
dock.alignment = "center";
dock.lengthMode = "fit";
dock.floating = dockCfg.floating !== "off";
dock.hiding = dockCfg.autohide === "on" ? "autohide" : "none";
dock.opacity = "translucent";

if (knownWidgetTypes.indexOf("org.kwickos.dock") >= 0) {
    var kd = dock.addWidget("org.kwickos.dock");
    kd.currentConfigGroup = ["General"];
    kd.writeConfig("launchers", launchers);
    kd.writeConfig("magnify", dockCfg.magnify === "off" ? "false" : "true");
} else {
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
}
