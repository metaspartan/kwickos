// KwickOS macOS (liquid glass) layout — applied by kwick-layout and at first login.
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

// ── Liquid-glass floating menu bar ──────────────────────────────────────────
var top = new Panel;
top.location = "top";
top.height = Math.round(gridUnit * 1.5);
top.floating = true;               // macOS 27 style: floating pill, not edge-to-edge
top.hiding = "none";
top.opacity = "translucent";
top.alignment = "left";
top.lengthMode = "fill";

// App launcher (KwickOS mark)
var k = top.addWidget("org.kde.plasma.kickoff");
k.currentConfigGroup = ["General"];
k.writeConfig("icon", "kwick-start");
k.writeConfig("showAppsByName", "true");

// Global menu for the focused app (macOS-style)
top.addWidget("org.kde.plasma.appmenu");

// Spacer pushes tray + clock to the right
top.addWidget("org.kde.plasma.panelspacer");

// Small margin separator before the tray for breathing room
var sep1 = top.addWidget("org.kde.plasma.marginsseparator");
top.addWidget("org.kde.plasma.systemtray");

// Clock: 12-hour with AM/PM and date — macOS style
var clk = top.addWidget("org.kde.plasma.digitalclock");
clk.currentConfigGroup = ["Appearance"];
clk.writeConfig("showDate", "true");
clk.writeConfig("dateFormat", "custom");
clk.writeConfig("customDateFormat", "ddd d MMM");
clk.writeConfig("dateDisplayFormat", "BesideTime");
clk.writeConfig("use24hFormat", "false");
clk.writeConfig("showSeconds", "false");
clk.writeConfig("fontFamily", "Inter");
clk.writeConfig("fontWeight", "500");
clk.writeConfig("fontSize", "10");

// Margin separator after clock
var sep2 = top.addWidget("org.kde.plasma.marginsseparator");

// ── Floating glass dock ─────────────────────────────────────────────────────
var dock = new Panel;
dock.location = "bottom";
dock.height = Math.round(gridUnit * 3.6);
dock.alignment = "center";
dock.lengthMode = "fit";
dock.floating = true;
dock.hiding = "dodgewindows";
dock.opacity = "translucent";
// Apple-style: extra breathing room on each side of the dock
var dl = dock.addWidget("org.kde.plasma.marginsseparator");
var t = dock.addWidget("org.kde.plasma.icontasks");
t.currentConfigGroup = ["General"];
t.writeConfig("launchers", launchers);
t.writeConfig("showOnlyCurrentDesktop", "false");
t.writeConfig("iconSpacing", "3");
t.writeConfig("indicateAudioStreams", "true");
t.writeConfig("showToolTips", "true");
t.writeConfig("groupingStrategy", "0");       // don't group
t.writeConfig("middleClickAction", "None");   // macOS: no middle-click close
var dr = dock.addWidget("org.kde.plasma.marginsseparator");
dock.addWidget("org.kde.plasma.trash");
