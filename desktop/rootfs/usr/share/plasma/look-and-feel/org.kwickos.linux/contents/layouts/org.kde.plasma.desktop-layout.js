var kwickScript = "/usr/share/kwick/plasma/linux.js";
var kwickBody = readFile(kwickScript);
if (kwickBody) {
    eval(kwickBody);
}
