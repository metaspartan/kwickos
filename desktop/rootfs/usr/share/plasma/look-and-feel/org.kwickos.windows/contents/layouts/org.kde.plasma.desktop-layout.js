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
    "applications:kwick-settings.desktop"
].join(",");
var fluent = knownWidgetTypes.indexOf("org.kwickos.start") >= 0;

var p = new Panel;
p.location = "bottom";
p.height = 48;
p.floating = false;
p.hiding = "none";
p.opacity = "translucent";

function gap(px) {
    var g = p.addWidget("org.kde.plasma.marginsseparator");
    g.currentConfigGroup = ["General"];
    g.writeConfig("margin", String(px));
}

function button(icon, title, command) {
    var b = p.addWidget("org.kwickos.taskbutton");
    b.currentConfigGroup = ["General"];
    b.writeConfig("icon", icon);
    b.writeConfig("title", title);
    b.writeConfig("command", command);
}

var lead = p.addWidget("org.kde.plasma.panelspacer");
lead.currentConfigGroup = ["General"];
lead.writeConfig("expanding", "false");
lead.writeConfig("length", fluent ? "176" : "260");
p.addWidget("org.kde.plasma.panelspacer");

if (fluent) {
    var start = p.addWidget("org.kwickos.start");
    start.globalShortcut = "Alt+F1";
    button("kwick-search", "Search", "qdbus6 org.kde.krunner /App org.kde.krunner.App.display");
    button("kwick-taskview", "Task View", "qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut Overview");
} else {
    var k = p.addWidget("org.kde.plasma.kickoff");
    k.currentConfigGroup = ["General"];
    k.writeConfig("icon", "kwick-start-fluent");
    gap(4);
    ["kwick-search", "kwick-taskview"].forEach(function (name) {
        var w = p.addWidget("org.kde.plasma.icon");
        w.currentConfigGroup = ["General"];
        w.writeConfig("url", "file:///usr/share/applications/" + name + ".desktop");
    });
    gap(4);
}

var t = p.addWidget("org.kde.plasma.icontasks");
t.currentConfigGroup = ["General"];
t.writeConfig("launchers", launchers);
t.writeConfig("showOnlyCurrentDesktop", "false");
t.writeConfig("iconSpacing", "0");
t.writeConfig("maxStripes", "1");

p.addWidget("org.kde.plasma.panelspacer");

var tray = p.addWidget("org.kde.plasma.systemtray");
tray.currentConfigGroup = [];
var trayInner = desktopById(tray.readConfig("SystrayContainmentId"));

if (fluent) {
    if (trayInner) {
        trayInner.currentConfigGroup = ["General"];
        trayInner.writeConfig("iconSpacing", "1");
        trayInner.writeConfig("hiddenItems", [
            "org.kde.plasma.volume", "org.kde.plasma.battery", "org.kde.plasma.networkmanagement",
            "org.kde.plasma.bluetooth", "org.kde.plasma.brightness", "org.kde.plasma.notifications",
            "org.kde.plasma.mediacontroller", "org.kde.plasma.clipboard", "org.kwickos.vpn"
        ]);
    }
    p.addWidget("org.kwickos.quicksettings");
    p.addWidget("org.kwickos.notificationcenter");
} else {
    gap(8);
    var c = p.addWidget("org.kde.plasma.digitalclock");
    c.currentConfigGroup = ["Appearance"];
    c.writeConfig("showDate", "true");
    c.writeConfig("dateFormat", "custom");
    c.writeConfig("customDateFormat", "M/d/yyyy");
    c.writeConfig("dateDisplayFormat", "BelowTime");
    c.writeConfig("use24hFormat", 0);
    c.writeConfig("showSeconds", "false");
    c.writeConfig("fontFamily", "Selawik");
    c.writeConfig("fontWeight", "400");
    c.writeConfig("fontSize", "9");
    c.writeConfig("autoFontAndSize", "false");
    gap(8);
}
