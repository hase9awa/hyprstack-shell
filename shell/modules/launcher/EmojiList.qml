pragma ComponentBehavior: Bound

import "items"
import QtQuick
import Quickshell
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

Item {
    id: root

    required property SearchBar search
    required property ScreenState screenState

    // The launcher drives whichever list is showing through these.
    readonly property alias count: grid.count
    readonly property alias currentItem: grid.currentItem
    readonly property string query: search.text.split(" ").slice(1).join(" ")

    function incrementCurrentIndex(): void {
        grid.moveCurrentIndexRight();
    }

    function decrementCurrentIndex(): void {
        grid.moveCurrentIndexLeft();
    }

    GridView {
        id: grid

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: sidebar.left
        anchors.rightMargin: Tokens.spacing.small

        clip: true
        cellWidth: 48 * Tokens.scale
        cellHeight: 48 * Tokens.scale

        model: ScriptModel {
            values: Emoji.query(root.query)
            onValuesChanged: grid.currentIndex = 0
        }

        highlightFollowsCurrentItem: false
        highlight: StyledRect {
            radius: Tokens.rounding.medium
            color: Colours.palette.m3onSurface
            opacity: 0.08

            x: grid.currentItem?.x ?? 0
            y: grid.currentItem?.y ?? 0
            implicitWidth: grid.cellWidth
            implicitHeight: grid.cellHeight

            Behavior on x {
                Anim {}
            }

            Behavior on y {
                Anim {}
            }
        }

        delegate: EmojiItem {
            screenState: root.screenState
        }

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: grid
        }
    }

    StyledRect {
        id: sidebar

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        implicitWidth: 44 * Tokens.scale
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        StyledListView {
            id: groupList

            anchors.fill: parent
            anchors.margins: Tokens.padding.extraSmall

            clip: true
            spacing: Tokens.spacing.extraSmall
            model: Emoji.groups

            delegate: StyledRect {
                id: groupEntry

                required property var modelData
                readonly property bool selected: Emoji.group === modelData.id && !root.query

                implicitWidth: groupList.width
                implicitHeight: implicitWidth
                radius: Tokens.rounding.full
                color: Qt.alpha(Colours.palette.m3secondaryContainer, selected ? 1 : 0)

                StateLayer {
                    color: groupEntry.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                    onClicked: {
                        Emoji.group = groupEntry.modelData.id;
                        // Browsing a group is not compatible with a search
                        // across all of them.
                        root.search.text = `${GlobalConfig.launcher.actionPrefix}emoji `;
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: groupEntry.modelData.icon
                    color: groupEntry.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                    fill: groupEntry.selected ? 1 : 0
                }
            }

            // Anything typed can be kept as a character of its own.
            footer: Item {
                implicitWidth: groupList.width
                implicitHeight: implicitWidth + Tokens.spacing.extraSmall

                IconButton {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    type: IconButton.Tonal
                    icon: "add"
                    disabled: !root.query.trim()
                    Accessible.name: Tr.tr("Add what was typed")
                    onClicked: {
                        Emoji.addCustom(root.query);
                        root.search.text = `${GlobalConfig.launcher.actionPrefix}emoji `;
                    }
                }
            }
        }
    }
}
