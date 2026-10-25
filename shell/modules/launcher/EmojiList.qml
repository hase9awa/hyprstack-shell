pragma ComponentBehavior: Bound

import "items"
import QtQuick
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

    property bool addHovered

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

        // A plain array rather than a ScriptModel: picking a group replaces
        // every entry, and reconciling the old list against the new one
        // costs more than rebuilding the view outright.
        model: Emoji.query(root.query)
        onModelChanged: currentIndex = 0

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
        id: hint

        anchors.right: sidebar.left
        anchors.verticalCenter: sidebar.bottom
        anchors.verticalCenterOffset: -(sidebar.width / 2)
        anchors.rightMargin: Tokens.spacing.small

        visible: root.addHovered
        implicitWidth: hintText.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: hintText.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.small
        color: Colours.palette.m3inverseSurface
        z: 1

        StyledText {
            id: hintText

            anchors.centerIn: parent
            text: root.query.trim() ? Tr.tr("Add \"%1\"").arg(root.query.trim()) : Tr.tr("Type something to add it")
            color: Colours.palette.m3inverseOnSurface
            font: Tokens.font.body.small
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

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: addButton.top
            anchors.margins: Tokens.padding.extraSmall
            anchors.bottomMargin: Tokens.spacing.small

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
        }

        // Anything typed can be kept as a character of its own. It stays
        // below the strip so eighteen groups cannot push it out of reach.
        IconButton {
            id: addButton

            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: Tokens.padding.extraSmall

            implicitWidth: sidebar.width - Tokens.padding.extraSmall * 2
            implicitHeight: implicitWidth
            type: IconButton.Tonal
            icon: "add"
            disabled: !root.query.trim()
            Accessible.name: Tr.tr("Add what was typed")
            onHoveredChanged: root.addHovered = hovered
            onClicked: {
                Emoji.addCustom(root.query);
                root.search.text = `${GlobalConfig.launcher.actionPrefix}emoji `;
            }
        }

        // A disabled button takes no hover of its own, and the hint is
        // wanted exactly while it is disabled.
        MouseArea {
            anchors.fill: addButton
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onContainsMouseChanged: root.addHovered = containsMouse
        }
    }
}
