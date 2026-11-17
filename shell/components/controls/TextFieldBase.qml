import QtQuick
import QtQuick.Templates
import Hyprstack.Config
import qs.components
import qs.services

TextField {
    id: root

    property bool inputTextVisible: true
    property color textColor: Colours.palette.m3onSurface
    property color textSelectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)

    implicitWidth: contentWidth + leftPadding + rightPadding
    implicitHeight: contentHeight + topPadding + bottomPadding

    color: inputTextVisible ? textColor : "transparent"
    placeholderTextColor: Colours.palette.m3onSurfaceVariant // No anim cause placeholder is custom
    selectionColor: inputTextVisible ? textSelectionColor : "transparent"
    selectedTextColor: color

    font: Tokens.font.body.small
    renderType: TextField.QtRendering
    cursorVisible: !readOnly
    verticalAlignment: TextInput.AlignVCenter

    cursorDelegate: Item {}

    Behavior on textColor {
        CAnim {}
    }

    Behavior on textSelectionColor {
        CAnim {}
    }

    StyledRect {
        id: cursor

        property bool disableBlink
        visible: root.inputTextVisible

        x: root.cursorRectangle.x
        y: root.cursorRectangle.y
        implicitWidth: 1.5 * Tokens.scale
        implicitHeight: root.cursorRectangle.height

        color: Colours.palette.m3primary
        radius: Tokens.rounding.large

        Connections {
            function onCursorPositionChanged(): void {
                if (root.activeFocus && root.cursorVisible) {
                    cursor.opacity = 1;
                    cursor.disableBlink = true;
                    enableBlink.restart();
                }
            }

            target: root
        }

        Timer {
            id: enableBlink

            interval: 500
            onTriggered: cursor.disableBlink = false
        }

        Timer {
            running: root.activeFocus && root.cursorVisible && !cursor.disableBlink
            repeat: true
            triggeredOnStart: true
            interval: 500
            onTriggered: parent.opacity = parent.opacity === 1 ? 0 : 1
        }

        Binding {
            when: !root.activeFocus || !root.cursorVisible
            cursor.opacity: 0
        }

        Behavior on x {
            Anim {
                easing.bezierCurve: [0.2, 1, 0.21, 1, 1, 1] // Damped variant of fast spatial curve
                duration: Tokens.anim.durations.expressiveFastEffects
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.StandardSmall
            }
        }
    }
}
