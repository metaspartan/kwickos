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
    "applications:kwick-files.desktop", "applications:firefox-esr.desktop",
    "applications:kwick-terminal.desktop", "applications:kwick-editor.desktop",
    "applications:kwick-software.desktop", "applications:steam.desktop",
    "applications:kwick-settings.desktop"
].join(",");

var p = new Panel;
p.location = "bottom";
p.height = 48;
p.floating = false;
p.hiding = "none";
p.opacity = "translucent";

var lead = p.addWidget("org.kde.plasma.panelspacer");
lead.currentConfigGroup = ["Configuration", "General"];
lead.writeConfig("expanding", "false");
lead.writeConfig("length", "260");

var l2 = p.addWidget("org.kde.plasma.panelspacer");

var k = p.addWidget("org.kde.plasma.kickoff");
k.currentConfigGroup = ["General"];
k.writeConfig("icon", "kwick-start-fluent");
var gapK = p.addWidget("org.kde.plasma.marginsseparator");
gapK.currentConfigGroup = ["General"];
gapK.writeConfig("margin", "4");

var search = p.addWidget("org.kde.plasma.icon");
search.currentConfigGroup = ["General"];
search.writeConfig("url", "file:///usr/share/applications/kwick-search.desktop");
var view = p.addWidget("org.kde.plasma.icon");
view.currentConfigGroup = ["General"];
view.writeConfig("url", "file:///usr/share/applications/kwick-taskview.desktop");
var gapV = p.addWidget("org.kde.plasma.marginsseparator");
gapV.currentConfigGroup = ["General"];
gapV.writeConfig("margin", "4");

var t = p.addWidget("org.kde.plasma.icontasks");
t.currentConfigGroup = ["General"];
t.writeConfig("launchers", launchers);
t.writeConfig("showOnlyCurrentDesktop", "false");
t.writeConfig("iconSpacing", "2");
t.writeConfig("maxStripes", "1");

p.addWidget("org.kde.plasma.panelspacer");

var gapT = p.addWidget("org.kde.plasma.marginsseparator");
gapT.currentConfigGroup = ["General"];
gapT.writeConfig("margin", "8");
p.addWidget("org.kde.plasma.systemtray");
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
c.writeConfig("fontSize", "8");
c.writeConfig("autoFontAndSize", "false");

var edge = p.addWidget("org.kde.plasma.marginsseparator");
edge.currentConfigGroup = ["General"];
edge.writeConfig("margin", "8");

