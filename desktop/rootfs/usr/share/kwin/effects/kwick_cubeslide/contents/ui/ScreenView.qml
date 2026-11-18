import QtQuick
import QtQuick3D
import org.kde.kwin as KWinComponents

Item {
    id: root

    readonly property QtObject targetScreen: KWinComponents.SceneView.screen
    readonly property int faceCount: Math.max(1, KWinComponents.Workspace.desktops.length)
    readonly property real angleTick: 360 / faceCount
    readonly property real faceDistance: 0.5 * width / Math.tan(angleTick * Math.PI / 360)
    readonly property real viewDistance: 0.5 * height / Math.tan(0.5 * camera.fieldOfView * Math.PI / 180)
    readonly property real pull: effect.pull
    readonly property real cameraRadius: faceDistance + viewDistance + pull * effect.configuration.PullBack * (faceDistance + viewDistance) * 1.1
    readonly property real cameraHeight: pull * height * 0.46
    readonly property real tilt: Math.atan2(cameraHeight, cameraRadius) * 180 / Math.PI
    readonly property real floorY: -height / 2 - 14
    readonly property real lift: effect.configuration.WindowLift
    readonly property real reflect: effect.configuration.Reflection === undefined ? 0.5 : effect.configuration.Reflection

    Texture {
        id: wallTex
        sourceItem: Item {
            width: root.width
            height: root.height
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#26305c" }
                    GradientStop { position: 1.0; color: "#0c0f1f" }
                }
            }
            Repeater {
                model: KWinComponents.WindowFilterModel {
                    activity: KWinComponents.Workspace.currentActivity
                    desktop: KWinComponents.Workspace.currentDesktop
                    screenName: root.targetScreen.name
                    windowModel: KWinComponents.WindowModel {}
                }
                delegate: KWinComponents.WindowThumbnail {
                    required property var model
                    visible: model.window.desktopWindow
                    wId: model.window.internalId
                    anchors.fill: parent
                }
            }
            Rectangle {
                anchors.fill: parent
                color: "#060916"
                opacity: 0.74
            }
            Canvas {
                anchors.fill: parent
                renderTarget: Canvas.Image
                renderStrategy: Canvas.Immediate
                onPaint: {
                    const c = getContext("2d");
                    c.reset();
                    const glow = c.createRadialGradient(width / 2, height * 0.5, 0, width / 2, height * 0.5, Math.max(width, height) * 0.55);
                    glow.addColorStop(0, "rgba(96,128,214,0.46)");
                    glow.addColorStop(0.45, "rgba(52,74,150,0.2)");
                    glow.addColorStop(1, "rgba(20,30,70,0)");
                    c.fillStyle = glow;
                    c.fillRect(0, 0, width, height);
                    const g = c.createRadialGradient(width / 2, height * 0.46, height * 0.3, width / 2, height * 0.5, Math.max(width, height) * 0.8);
                    g.addColorStop(0, "rgba(0,0,0,0)");
                    g.addColorStop(1, "rgba(0,0,0,0.55)");
                    c.fillStyle = g;
                    c.fillRect(0, 0, width, height);
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
            }
        }
    }

    Texture {
        id: floorTex
        sourceItem: Canvas {
            width: 512
            height: 512
            renderTarget: Canvas.Image
            renderStrategy: Canvas.Immediate
            onPaint: {
                const c = getContext("2d");
                c.reset();
                const g = c.createRadialGradient(256, 256, 20, 256, 256, 256);
                g.addColorStop(0, "rgba(120,150,210,0.55)");
                g.addColorStop(0.5, "rgba(70,95,150,0.4)");
                g.addColorStop(1, "rgba(30,45,80,0)");
                c.fillStyle = g;
                c.fillRect(0, 0, 512, 512);
            }
            Component.onCompleted: requestPaint()
        }
    }

    Texture {
        id: contactTex
        sourceItem: Canvas {
            width: 256
            height: 256
            renderTarget: Canvas.Image
            renderStrategy: Canvas.Immediate
            onPaint: {
                const c = getContext("2d");
                c.reset();
                const g = c.createRadialGradient(128, 128, 10, 128, 128, 128);
                g.addColorStop(0, "rgba(0,0,0,0.85)");
                g.addColorStop(0.55, "rgba(0,0,0,0.35)");
                g.addColorStop(1, "rgba(0,0,0,0)");
                c.fillStyle = g;
                c.fillRect(0, 0, 256, 256);
            }
            Component.onCompleted: requestPaint()
        }
    }

    function softBox(c, size, margin, peak, power) {
        const img = c.createImageData(size, size);
        const half = size / 2 - margin;
        for (let y = 0; y < size; y++) {
            for (let x = 0; x < size; x++) {
                const dx = Math.max(0, Math.abs(x + 0.5 - size / 2) - half + margin * 0.5);
                const dy = Math.max(0, Math.abs(y + 0.5 - size / 2) - half + margin * 0.5);
                const d = Math.sqrt(dx * dx + dy * dy) / (margin * 0.5);
                const a = Math.pow(Math.max(0, 1 - d), power) * peak;
                const i = (y * size + x) * 4;
                img.data[i] = 0;
                img.data[i + 1] = 0;
                img.data[i + 2] = 4;
                img.data[i + 3] = Math.round(255 * a);
            }
        }
        c.putImageData(img, 0, 0);
    }

    Texture {
        id: shadowTex
        sourceItem: Canvas {
            width: 128
            height: 128
            renderTarget: Canvas.Image
            renderStrategy: Canvas.Immediate
            onPaint: {
                const c = getContext("2d");
                c.reset();
                root.softBox(c, 128, 44, 0.62, 1.7);
            }
            Component.onCompleted: requestPaint()
        }
    }

    Texture {
        id: contactTex2
        sourceItem: Canvas {
            width: 128
            height: 128
            renderTarget: Canvas.Image
            renderStrategy: Canvas.Immediate
            onPaint: {
                const c = getContext("2d");
                c.reset();
                root.softBox(c, 128, 16, 0.85, 2.2);
            }
            Component.onCompleted: requestPaint()
        }
    }

    Texture {
        id: edgeTex
        generateMipmaps: true
        mipFilter: Texture.Linear
        sourceItem: Canvas {
            width: 1024
            height: 576
            renderTarget: Canvas.Image
            renderStrategy: Canvas.Immediate
            onPaint: {
                const c = getContext("2d");
                c.reset();
                const g = c.createLinearGradient(0, 0, 0, height);
                g.addColorStop(0, "rgba(150,185,255,0.10)");
                g.addColorStop(0.5, "rgba(150,185,255,0.0)");
                g.addColorStop(1, "rgba(150,185,255,0.05)");
                c.fillStyle = g;
                c.fillRect(0, 0, width, height);
                c.lineWidth = 12;
                c.strokeStyle = "rgba(140,175,255,0.16)";
                c.strokeRect(7, 7, width - 14, height - 14);
                c.lineWidth = 3;
                c.strokeStyle = "rgba(225,238,255,0.92)";
                c.strokeRect(1.5, 1.5, width - 3, height - 3);
            }
            Component.onCompleted: requestPaint()
        }
    }

    Texture {
        id: glintTex
        sourceItem: Canvas {
            width: 128
            height: 128
            renderTarget: Canvas.Image
            renderStrategy: Canvas.Immediate
            onPaint: {
                const c = getContext("2d");
                c.reset();
                const img = c.createImageData(128, 128);
                for (let y = 0; y < 128; y++) {
                    for (let x = 0; x < 128; x++) {
                        const u = (x + 0.5) / 128 * 2 - 1;
                        const v = (y + 0.5) / 128 * 2 - 1;
                        const band = Math.pow(Math.max(0, 1 - Math.abs(u)), 2.4);
                        const fall = Math.pow(Math.max(0, 1 - Math.abs(v)), 0.7);
                        const i = (y * 128 + x) * 4;
                        img.data[i] = 255;
                        img.data[i + 1] = 255;
                        img.data[i + 2] = 255;
                        img.data[i + 3] = Math.round(255 * band * fall);
                    }
                }
                c.putImageData(img, 0, 0);
            }
            Component.onCompleted: requestPaint()
        }
    }

    Texture {
        id: sheenTex
        sourceItem: Canvas {
            width: 256
            height: 256
            renderTarget: Canvas.Image
            renderStrategy: Canvas.Immediate
            onPaint: {
                const c = getContext("2d");
                c.reset();
                const g = c.createLinearGradient(0, 0, 256, 256);
                g.addColorStop(0, "rgba(255,255,255,0.55)");
                g.addColorStop(0.32, "rgba(255,255,255,0.12)");
                g.addColorStop(0.5, "rgba(255,255,255,0)");
                g.addColorStop(1, "rgba(255,255,255,0.08)");
                c.fillStyle = g;
                c.fillRect(0, 0, 256, 256);
            }
            Component.onCompleted: requestPaint()
        }
    }

    Texture {
        id: fadeTex
        sourceItem: Canvas {
            width: 8
            height: 256
            renderTarget: Canvas.Image
            renderStrategy: Canvas.Immediate
            onPaint: {
                const c = getContext("2d");
                c.reset();
                const g = c.createLinearGradient(0, 256, 0, 0);
                g.addColorStop(0, "rgba(14,20,44,0.0)");
                g.addColorStop(0.2, "rgba(14,20,44,0.42)");
                g.addColorStop(0.55, "rgba(14,20,44,0.86)");
                g.addColorStop(1, "rgba(14,20,44,1.0)");
                c.fillStyle = g;
                c.fillRect(0, 0, 8, 256);
            }
            Component.onCompleted: requestPaint()
        }
    }

    function faceBrightness(index) {
        let d = Math.abs(((effect.azimuth - angleTick * index) % 360 + 540) % 360 - 180);
        const k = Math.max(0, Math.cos(d * Math.PI / 180));
        return 0.62 + 0.38 * Math.pow(k, 0.8);
    }

    Component {
        id: worldC
        Node {
        id: world
        property bool mirror: false

        Repeater3D {
            model: KWinComponents.VirtualDesktopModel {}
            delegate: Node {
                id: face
                required property QtObject desktop
                required property int index
                readonly property real bright: root.faceBrightness(index)
                readonly property real a: root.angleTick * index * Math.PI / 180
                readonly property real rel: ((effect.azimuth - root.angleTick * index) % 360 + 540) % 360 - 180
                readonly property real facing: Math.max(0, Math.cos(rel * Math.PI / 180))
                readonly property real rim: Math.min(1, 0.2 + 2.4 * (1 - facing))
                readonly property real glintU: Math.max(-1, Math.min(1, rel / 42))
                readonly property real glintGain: facing * Math.max(0, 1 - Math.pow(Math.abs(glintU), 3))

                visible: root.cameraRadius * Math.cos((effect.azimuth - root.angleTick * index) * Math.PI / 180) - root.faceDistance > 0
                eulerRotation.y: root.angleTick * index
                position: Qt.vector3d(root.faceDistance * Math.sin(a), 0, root.faceDistance * Math.cos(a))

                Model {
                    source: "#Rectangle"
                    scale: Qt.vector3d(root.width / 100, root.height / 100, 1)
                    position: Qt.vector3d(0, 0, -2)
                    materials: PrincipledMaterial {
                        lighting: PrincipledMaterial.NoLighting
                        cullMode: Material.NoCulling
                        baseColor: Qt.rgba(0.09 * face.bright, 0.09 * face.bright, 0.12 * face.bright, 1)
                    }
                }

                Repeater3D {
                    model: KWinComponents.WindowFilterModel {
                        activity: KWinComponents.Workspace.currentActivity
                        desktop: face.desktop
                        screenName: root.targetScreen.name
                        windowModel: KWinComponents.WindowModel {}
                    }
                    delegate: Node {
                        id: slot
                        required property var model
                        readonly property QtObject w: model.window
                        readonly property bool plain: w.desktopWindow || w.dock
                        readonly property real z0: plain ? (w.dock ? root.lift * 0.5 * root.pull : 0) : root.lift * root.pull * (0.7 + 0.3 * Math.min(8, Math.max(0, w.stackingOrder)) / 8) * 3.4
                        readonly property real cx: w.x - root.targetScreen.geometry.x + w.width / 2 - root.width / 2
                        readonly property real cy: root.height / 2 - (w.y - root.targetScreen.geometry.y + w.height / 2)
                        visible: !w.minimized

                        Model {
                            visible: !slot.plain && !slot.w.minimized && root.pull > 0.12
                            source: "#Rectangle"
                            scale: Qt.vector3d((Math.max(1, slot.w.width) + 70 + 0.35 * slot.z0) / 100, (Math.max(1, slot.w.height) + 70 + 0.35 * slot.z0) / 100, 1)
                            position: Qt.vector3d(slot.cx + 0.12 * slot.z0, slot.cy - 0.22 * slot.z0, slot.z0 * 0.06)
                            materials: PrincipledMaterial {
                                lighting: PrincipledMaterial.NoLighting
                                cullMode: Material.NoCulling
                                alphaMode: PrincipledMaterial.Blend
                                baseColor: Qt.rgba(1, 1, 1, 0.55 + 0.45 * root.pull)
                                baseColorMap: shadowTex
                            }
                        }

                        Model {
                            visible: !slot.plain && !slot.w.minimized && root.pull > 0.12
                            source: "#Rectangle"
                            scale: Qt.vector3d((Math.max(1, slot.w.width) + 22 + 0.1 * slot.z0) / 100, (Math.max(1, slot.w.height) + 22 + 0.1 * slot.z0) / 100, 1)
                            position: Qt.vector3d(slot.cx + 0.03 * slot.z0, slot.cy - 0.05 * slot.z0, 1.5)
                            materials: PrincipledMaterial {
                                lighting: PrincipledMaterial.NoLighting
                                cullMode: Material.NoCulling
                                alphaMode: PrincipledMaterial.Blend
                                baseColor: Qt.rgba(1, 1, 1, Math.min(1, root.pull * 1.6))
                                baseColorMap: contactTex2
                            }
                        }

                        Model {
                            source: "#Rectangle"
                            scale: Qt.vector3d(Math.max(1, slot.w.width) / 100, Math.max(1, slot.w.height) / 100, 1)
                            position: Qt.vector3d(slot.cx, slot.cy, slot.z0)
                            materials: PrincipledMaterial {
                                lighting: PrincipledMaterial.NoLighting
                                cullMode: Material.NoCulling
                                alphaMode: PrincipledMaterial.Blend
                                baseColor: Qt.rgba(face.bright, face.bright, face.bright, 1)
                                baseColorMap: Texture {
                                    sourceItem: Item {
                                        width: Math.max(1, slot.w.width)
                                        height: Math.max(1, slot.w.height)
                                        KWinComponents.WindowThumbnail {
                                            anchors.fill: parent
                                            wId: slot.w.internalId
                                        }
                                    }
                                }
                            }
                        }

                        Model {
                            visible: !world.mirror && !slot.plain && !slot.w.minimized && root.pull > 0.12
                            source: "#Rectangle"
                            scale: Qt.vector3d(Math.max(1, slot.w.width) / 100, Math.max(1, slot.w.height) / 100, 1)
                            position: Qt.vector3d(slot.cx, slot.cy, slot.z0 + 0.6)
                            materials: PrincipledMaterial {
                                lighting: PrincipledMaterial.NoLighting
                                cullMode: Material.NoCulling
                                alphaMode: PrincipledMaterial.Blend
                                baseColor: Qt.rgba(1, 1, 1, Math.min(1, root.pull * 1.4) * (0.45 + 0.55 * face.rim))
                                baseColorMap: Texture {
                                    generateMipmaps: true
                                    mipFilter: Texture.Linear
                                    sourceItem: Canvas {
                                        width: Math.max(8, slot.w.width)
                                        height: Math.max(8, slot.w.height)
                                        renderTarget: Canvas.Image
                                        renderStrategy: Canvas.Immediate
                                        onWidthChanged: requestPaint()
                                        onHeightChanged: requestPaint()
                                        onPaint: {
                                            const c = getContext("2d");
                                            c.reset();
                                            const r = 11;
                                            const rr = function (inset) {
                                                c.beginPath();
                                                c.moveTo(inset + r, inset);
                                                c.arcTo(width - inset, inset, width - inset, height - inset, r);
                                                c.arcTo(width - inset, height - inset, inset, height - inset, r);
                                                c.arcTo(inset, height - inset, inset, inset, r);
                                                c.arcTo(inset, inset, width - inset, inset, r);
                                                c.closePath();
                                            };
                                            c.lineWidth = 7;
                                            c.strokeStyle = "rgba(160,195,255,0.13)";
                                            rr(4);
                                            c.stroke();
                                            c.lineWidth = 1.6;
                                            c.strokeStyle = "rgba(235,244,255,0.85)";
                                            rr(0.8);
                                            c.stroke();
                                        }
                                        Component.onCompleted: requestPaint()
                                    }
                                }
                            }
                        }

                        Model {
                            visible: !world.mirror && !slot.plain && !slot.w.minimized && root.pull > 0.12
                            source: "#Rectangle"
                            scale: Qt.vector3d(Math.max(1, slot.w.width) * 0.34 / 100, Math.max(1, slot.w.height) / 100, 1)
                            position: Qt.vector3d(slot.cx + face.glintU * Math.max(1, slot.w.width) * 0.42, slot.cy, slot.z0 + 1.2)
                            materials: PrincipledMaterial {
                                lighting: PrincipledMaterial.NoLighting
                                cullMode: Material.NoCulling
                                alphaMode: PrincipledMaterial.Blend
                                baseColor: Qt.rgba(1, 1, 1, 0.3 * root.pull * face.glintGain)
                                baseColorMap: glintTex
                            }
                        }
                    }
                }

                Model {
                    visible: !world.mirror && root.faceCount === 4 && face.index === 0
                    source: "#Rectangle"
                    eulerRotation.x: -90
                    position: Qt.vector3d(0, root.height / 2 + 1, -root.faceDistance)
                    scale: Qt.vector3d(root.width / 100, root.width / 100, 1)
                    materials: PrincipledMaterial {
                        lighting: PrincipledMaterial.NoLighting
                        cullMode: Material.NoCulling
                        alphaMode: PrincipledMaterial.Blend
                        baseColor: Qt.rgba(0.4, 0.55, 0.95, 0.34 * root.pull)
                        baseColorMap: edgeTex
                    }
                }

                Model {
                    visible: !world.mirror && root.pull > 0.04
                    source: "#Rectangle"
                    scale: Qt.vector3d(root.width / 100, root.height / 100, 1)
                    position: Qt.vector3d(0, 0, 4)
                    materials: PrincipledMaterial {
                        lighting: PrincipledMaterial.NoLighting
                        cullMode: Material.NoCulling
                        alphaMode: PrincipledMaterial.Blend
                        baseColor: Qt.rgba(1, 1, 1, Math.min(1, root.pull * 1.5) * (0.5 + 0.5 * face.rim))
                        baseColorMap: edgeTex
                    }
                }

                Model {
                    visible: !world.mirror && root.pull > 0.08
                    source: "#Rectangle"
                    scale: Qt.vector3d(root.width * 0.3 / 100, root.height / 100, 1)
                    position: Qt.vector3d(face.glintU * root.width * 0.34, 0, root.lift * 1.7 + 6)
                    materials: PrincipledMaterial {
                        lighting: PrincipledMaterial.NoLighting
                        cullMode: Material.NoCulling
                        alphaMode: PrincipledMaterial.Blend
                        baseColor: Qt.rgba(1, 1, 1, 0.34 * root.pull * face.glintGain)
                        baseColorMap: glintTex
                    }
                }

                Model {
                    visible: !world.mirror && root.pull > 0.12
                    source: "#Rectangle"
                    scale: Qt.vector3d(root.width / 100, root.height / 100, 1)
                    position: Qt.vector3d(0, 0, root.lift * 1.7 + 5)
                    materials: PrincipledMaterial {
                        lighting: PrincipledMaterial.NoLighting
                        cullMode: Material.NoCulling
                        alphaMode: PrincipledMaterial.Blend
                        baseColor: Qt.rgba(1, 1, 1, 0.5 * root.pull * (1 - 0.5 * (1 - face.bright)))
                        baseColorMap: sheenTex
                    }
                }

                Model {
                    visible: world.mirror
                    source: "#Rectangle"
                    scale: Qt.vector3d(root.width / 100, root.height / 100, 1)
                    position: Qt.vector3d(0, 0, root.lift * 1.7 + 8)
                    materials: PrincipledMaterial {
                        lighting: PrincipledMaterial.NoLighting
                        cullMode: Material.NoCulling
                        alphaMode: PrincipledMaterial.Blend
                        baseColorMap: fadeTex
                    }
                }
            }
        }
    }
    }

    View3D {
        id: view
        anchors.fill: parent
        renderMode: View3D.Underlay

        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color
            clearColor: effect.configuration.BackgroundColor
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
        }

        PerspectiveCamera {
            id: camera
            clipNear: 10.0
            clipFar: 100000.0
            fieldOfView: 40
            eulerRotation.y: effect.azimuth
            eulerRotation.x: -root.tilt
            position: {
                const r = root.cameraRadius;
                const phi = effect.azimuth * Math.PI / 180;
                return Qt.vector3d(r * Math.sin(phi), root.cameraHeight, r * Math.cos(phi));
            }

            Model {
                readonly property real dist: 30000
                readonly property real vh: 2 * dist * Math.tan(camera.fieldOfView * Math.PI / 360) * 1.25
                source: "#Rectangle"
                position: Qt.vector3d(0, 0, -dist)
                scale: Qt.vector3d(vh * root.width / root.height / 100, vh / 100, 1)
                materials: PrincipledMaterial {
                    lighting: PrincipledMaterial.NoLighting
                    cullMode: Material.NoCulling
                    baseColorMap: wallTex
                }
            }
        }

        Node {
            Model {
                source: "#Rectangle"
                eulerRotation.x: -90
                position: Qt.vector3d(0, root.floorY - 1, 0)
                scale: Qt.vector3d(root.faceDistance * 9 / 100, root.faceDistance * 9 / 100, 1)
                visible: root.pull > 0.02
                opacity: Math.min(1, root.pull * 3)
                materials: PrincipledMaterial {
                    lighting: PrincipledMaterial.NoLighting
                    cullMode: Material.NoCulling
                    alphaMode: PrincipledMaterial.Blend
                    baseColorMap: floorTex
                }
            }

            Loader3D {
                sourceComponent: worldC
                onLoaded: item.mirror = true
                visible: root.reflect > 0 && root.pull > 0.02
                opacity: root.reflect * Math.min(1, root.pull * 3)
                position: Qt.vector3d(0, 2 * root.floorY, 0)
                scale: Qt.vector3d(1, -1, 1)
            }

            Model {
                source: "#Rectangle"
                eulerRotation.x: -90
                position: Qt.vector3d(0, root.floorY, 0)
                scale: Qt.vector3d(root.faceDistance * 2.9 / 100, root.faceDistance * 2.9 / 100, 1)
                visible: root.pull > 0.02
                opacity: Math.min(1, root.pull * 3)
                materials: PrincipledMaterial {
                    lighting: PrincipledMaterial.NoLighting
                    cullMode: Material.NoCulling
                    alphaMode: PrincipledMaterial.Blend
                    baseColorMap: contactTex
                }
            }

            Loader3D {
                sourceComponent: worldC
            }
        }
    }
}
