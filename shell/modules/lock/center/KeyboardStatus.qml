pragma ComponentBehavior: Bound

import QtQuick
import Hyprstack.Config
import qs.components
import qs.services

// The layout the password is about to be typed in. A keyboard with one
// layout has nothing to say here; with more, this is what the user needs
// before typing rather than after the attempt has failed, so it stays up
// the whole time instead of appearing with the other warnings.
StyledRect {
    id: root

    readonly property var layouts: Hypr.keyboard?.layout.split(",") ?? []

    visible: root.layouts.length > 1
    implicitWidth: label.implicitWidth + Tokens.padding.large * 2
    implicitHeight: label.implicitHeight + Tokens.padding.extraSmall * 2

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full

    StyledText {
        id: label

        anchors.centerIn: parent

        animate: true
        text: Hypr.kbLayout
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.mono.small
    }
}
