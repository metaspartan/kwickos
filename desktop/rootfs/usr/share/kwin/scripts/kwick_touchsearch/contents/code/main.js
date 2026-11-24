registerTouchScreenEdge(KWin.ElectricTop, function () {
    callDBus("org.kde.kglobalaccel", "/component/kwick_spotlight", "org.kde.kglobalaccel.Component", "invokeShortcut", "toggle");
});
