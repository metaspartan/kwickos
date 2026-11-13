var kwickScript = "/usr/share/kwick/plasma/macos.js";
var kwickBody = readFile(kwickScript);
if (kwickBody) {
    eval(kwickBody);
}
