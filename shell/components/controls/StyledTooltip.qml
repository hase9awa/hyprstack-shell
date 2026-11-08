import QtQuick
import Hyprstack.Config
import qs.components
import qs.services

StyledRect {
    id: root

    property alias text: label.text
    property bool shown

    implicitWidth: label.implicitWidth + Tokens.padding.medium * 2
    implicitHeight: label.implicitHeight + Tokens.padding.small * 2

    radius: Tokens.rounding.small
    // A hint sits on top of whatever it explains, so it borrows the surface
    // of the panels rather than the inverted one, which shouts in a dark
    // theme.
    color: Colours.tPalette.m3surfaceContainerHighest
    border.width: 1
    border.color: Colours.palette.m3outlineVariant

    visible: opacity > 0
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.9

    StyledText {
        id: label

        anchors.centerIn: parent
        color: Colours.palette.m3onSurface
        font: Tokens.font.body.small
    }

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    Behavior on scale {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    // Wording that changes under a pointer that has not moved swaps over
    // instead of snapping.
    Behavior on text {
        SequentialAnimation {
            Anim {
                target: label
                property: "opacity"
                from: 1
                to: 0
                type: Anim.DefaultEffects
            }
            PropertyAction {}
            Anim {
                target: label
                property: "opacity"
                from: 0
                to: 1
                type: Anim.DefaultEffects
            }
        }
    }
}
