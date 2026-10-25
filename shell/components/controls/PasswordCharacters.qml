pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import M3Shapes
import Hyprstack.Config
import qs.components
import qs.services

// One shape per character typed. Each arrives as a shape of its own and
// settles into a circle a moment later, so a password still shows how long
// it is without showing what it is.
ListView {
    id: root

    required property string buffer
    property bool revealed
    property real characterSize: Tokens.font.body.medium.pointSize

    // What the shapes are drawn from, updated after the width has been
    // dealt with so a new character widens the strip rather than appearing
    // in a strip that has already grown.
    property string displayed

    readonly property int fullWidth: {
        let w = (count - 1) * spacing;
        for (let i = 0; i < count; i++)
            w += ((itemAtIndex(i) as CharItem)?.nonAnimWidthScale ?? 1) * implicitHeight;
        return w + implicitHeight; // Extra padding at ends
    }

    readonly property list<int> shapeQueue: {
        const shapes = [MaterialShape.Slanted, MaterialShape.Arch, MaterialShape.Fan, MaterialShape.Arrow, MaterialShape.SemiCircle, MaterialShape.Triangle, MaterialShape.Diamond, MaterialShape.ClamShell, MaterialShape.Pentagon, MaterialShape.Gem, MaterialShape.Sunny, MaterialShape.VerySunny, MaterialShape.Cookie4Sided, MaterialShape.Ghostish, MaterialShape.SoftBurst];
        for (let i = shapes.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [shapes[i], shapes[j]] = [shapes[j], shapes[i]];
        }
        return shapes;
    }

    function bindImWidth(): void {
        imWidthBehavior.enabled = false;
        implicitWidth = Qt.binding(() => fullWidth);
        imWidthBehavior.enabled = true;
    }

    onBufferChanged: {
        if (buffer.length > displayed.length)
            bindImWidth();
        else if (buffer.length === 0)
            implicitWidth = implicitWidth; // Hold the width through the removal
        displayed = buffer;
    }

    implicitWidth: fullWidth
    implicitHeight: characterSize

    orientation: Qt.Horizontal
    spacing: Tokens.spacing.extraSmall
    interactive: false

    model: ScriptModel {
        values: root.displayed.split("")
    }

    delegate: CharItem {}

    Behavior on implicitWidth {
        id: imWidthBehavior

        Anim {}
    }

    component CharItem: Item {
        id: char

        required property int index
        property real nonAnimWidthScale: 1

        implicitHeight: root.implicitHeight

        ListView.onRemove: {
            initAnim.stop();
            removeAnim.start();
        }

        SequentialAnimation {
            id: initAnim

            running: true

            ParallelAnimation {
                Anim {
                    target: char
                    property: "opacity"
                    from: 0
                    to: 1
                    type: Anim.DefaultEffects
                }
                Anim {
                    target: char
                    property: "scale"
                    from: 0
                    to: 1
                    type: Anim.FastSpatial
                }
                Anim {
                    target: char
                    property: "implicitWidth"
                    from: root.implicitHeight
                    to: root.implicitHeight * 1.3
                    type: Anim.DefaultEffects
                }
                PropertyAction {
                    target: char
                    property: "nonAnimWidthScale"
                    value: 1.5
                }
            }
            PauseAnimation {
                duration: 180 * Tokens.anim.durations.scale
            }
            PropertyAction {
                target: charShape
                property: "shape"
                value: MaterialShape.Circle
            }
            ParallelAnimation {
                Anim {
                    target: charShape
                    property: "scale"
                    to: 2 / 3
                    type: Anim.FastSpatial
                }
                Anim {
                    target: char
                    property: "implicitWidth"
                    to: root.implicitHeight
                    type: Anim.DefaultEffects
                }
                PropertyAction {
                    target: char
                    property: "nonAnimWidthScale"
                    value: 1
                }
            }
        }

        SequentialAnimation {
            id: removeAnim

            PropertyAction {
                target: char
                property: "ListView.delayRemove"
                value: true
            }
            ParallelAnimation {
                Anim {
                    type: Anim.DefaultEffects
                    target: char
                    property: "opacity"
                    to: 0
                }
                Anim {
                    target: char
                    property: "scale"
                    to: 0.5
                }
            }
            PropertyAction {
                target: char
                property: "ListView.delayRemove"
                value: false
            }
        }

        MaterialShape {
            id: charShape

            anchors.centerIn: parent
            implicitSize: root.implicitHeight * 1.5
            shape: root.shapeQueue[char.index % root.shapeQueue.length] ?? MaterialShape.Circle
            color: Colours.palette.m3onSurface

            opacity: root.revealed ? 0 : 1

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
            Behavior on color {
                CAnim {}
            }
        }

        Loader {
            anchors.centerIn: parent

            opacity: root.revealed ? 1 : 0
            active: opacity > 0
            asynchronous: true

            sourceComponent: StyledText {
                text: root.displayed[char.index]
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }
    }
}
