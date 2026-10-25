pragma ComponentBehavior: Bound

import QtQuick
import Hyprstack.Config
import qs.components
import qs.services

Item {
    id: root

    required property var modelData
    required property ScreenState screenState

    readonly property bool pinned: Emoji.pinned(modelData)
    readonly property bool mine: modelData.g === "custom"

    implicitWidth: GridView.view.cellWidth
    implicitHeight: GridView.view.cellHeight

    // The grid holds a hundred cells at once and swaps all of them when a
    // group is picked, so the hover state is a plain rectangle: a ripple
    // builds a shape per cell and that is what made switching stutter.
    StyledRect {
        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall / 2
        radius: Tokens.rounding.medium
        color: Colours.palette.m3onSurface
        opacity: layer.pressed ? 0.12 : layer.containsMouse ? 0.08 : 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        width: parent.width - Tokens.padding.small * 2
        horizontalAlignment: Text.AlignHCenter
        text: root.modelData.c
        // A kaomoji is a whole phrase of characters, so it only fits small.
        font: root.modelData.c.length > 2 ? Tokens.font.body.small : Tokens.font.title.large
        elide: Text.ElideRight
    }

    MaterialIcon {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Tokens.padding.extraSmall / 2
        visible: root.pinned
        text: "keep"
        color: Colours.palette.m3primary
        fontStyle: Tokens.font.icon.small
        fill: 1
    }

    // A character of one's own is the only kind that can be taken away. The
    // cross answers to either hover, so moving onto it does not hide it.
    MaterialIcon {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: Tokens.padding.extraSmall / 2
        visible: root.mine && (layer.containsMouse || remove.containsMouse)
        text: "close"
        color: Colours.palette.m3error
        fontStyle: Tokens.font.icon.small

        MouseArea {
            id: remove

            anchors.fill: parent
            anchors.margins: -Tokens.padding.extraSmall
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Emoji.removeCustom(root.modelData)
        }
    }

    MouseArea {
        id: layer

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        // Copying is what the picker is for; keeping a character around is
        // the second thing anyone wants from it.
        onClicked: event => {
            if (event.button === Qt.RightButton) {
                Emoji.togglePin(root.modelData);
                return;
            }
            Emoji.activate(root.modelData);
            root.screenState.launcher = false;
        }
    }
}
