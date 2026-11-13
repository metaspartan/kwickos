var kwickScript = "/usr/share/kwick/plasma/windows.js";
var kwickBody = readFile(kwickScript);
if (kwickBody) {
    eval(kwickBody);
}
