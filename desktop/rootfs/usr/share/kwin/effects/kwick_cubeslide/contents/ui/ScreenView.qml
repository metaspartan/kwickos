import QtQuick
import QtQuick3D
import org.kde.kwin as KWinComponents

Item {
    id: root

    readonly property QtObject targetScreen: KWinComponents.SceneView.screen
    readonly property size faceSize: Qt.size(width, height)
    readonly property int faceCount: Math.max(1, KWinComponents.Workspace.desktops.length)
    readonly property real angleTick: 360 / faceCount
    readonly property real faceDistance: 0.5 * width / Math.tan(angleTick * Math.PI / 360)
    readonly property real viewDistance: 0.5 * height / Math.tan(0.5 * camera.fieldOfView * Math.PI / 180)

    readonly property real cameraRadius: faceDistance + viewDistance + effect.pull * effect.configuration.PullBack * faceDistance * 2.0

    View3D {
        id: view
        anchors.fill: parent
        renderMode: View3D.Underlay

        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color
            clearColor: effect.configuration.BackgroundColor
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.Medium
        }

        PerspectiveCamera {
            id: camera
            clipNear: 10.0
            clipFar: 100000.0
            eulerRotation.y: effect.azimuth
            position: {
                const r = root.cameraRadius;
                const phi = effect.azimuth * Math.PI / 180;
                return Qt.vector3d(r * Math.sin(phi), 0, r * Math.cos(phi));
            }
        }

        Node {
            Repeater3D {
                model: KWinComponents.VirtualDesktopModel {}
                delegate: Node {
                    id: face
                    required property QtObject desktop
                    required property int index

                    visible: root.cameraRadius * Math.cos((effect.azimuth - root.angleTick * index) * Math.PI / 180) - root.faceDistance > 0
                    eulerRotation.y: root.angleTick * index
                    position: {
                        const m = Qt.matrix4x4();
                        m.rotate(root.angleTick * index, Qt.vector3d(0, 1, 0));
                        return m.times(Qt.vector3d(0, 0, root.faceDistance));
                    }

                    Model {
                        source: "#Rectangle"
                        scale: Qt.vector3d(root.width / 100, root.height / 100, 1)
                        position: Qt.vector3d(0, 0, -2)
                        materials: DefaultMaterial {
                            lighting: DefaultMaterial.NoLighting
                            cullMode: Material.BackFaceCulling
                            diffuseColor: "#14141b"
                        }
                    }

                    Repeater3D {
                        model: KWinComponents.WindowFilterModel {
                            activity: KWinComponents.Workspace.currentActivity
                            desktop: face.desktop
                            screenName: root.targetScreen.name
                            windowModel: KWinComponents.WindowModel {}
                        }
                        delegate: Model {
                            id: win
                            required property var model
                            readonly property QtObject w: model.window
                            readonly property bool plain: w.desktopWindow || w.dock
                            source: "#Rectangle"
                            visible: !w.minimized
                            scale: Qt.vector3d(Math.max(1, w.width) / 100, Math.max(1, w.height) / 100, 1)
                            position: Qt.vector3d(w.x - root.targetScreen.geometry.x + w.width / 2 - root.width / 2,
                                                  root.height / 2 - (w.y - root.targetScreen.geometry.y + w.height / 2),
                                                  plain ? (w.dock ? effect.configuration.WindowLift * 0.4 : 0) : effect.configuration.WindowLift * (0.6 + 0.4 * Math.min(8, Math.max(0, w.stackingOrder)) / 8) * (1 + effect.pull * 0.6))
                            materials: PrincipledMaterial {
                                lighting: PrincipledMaterial.NoLighting
                                cullMode: Material.BackFaceCulling
                                alphaMode: PrincipledMaterial.Blend
                                baseColorMap: Texture {
                                    sourceItem: Item {
                                        width: Math.max(1, win.w.width)
                                        height: Math.max(1, win.w.height)
                                        KWinComponents.WindowThumbnail {
                                            anchors.fill: parent
                                            wId: win.w.internalId
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
