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
        // A kaomoji is a whole phrase and a character of one's own can be
        // anything, so the cells grow to whatever the longest entry on show
        // needs rather than cutting it off at an emoji's width.
        cellWidth: {
            let needed = 0;
            for (const metrics of [m0, m1, m2, m3, m4, m5, m6, m7])
                needed = Math.max(needed, metrics.width);
            return Math.min(width, Math.max(48 * Tokens.scale, needed + Tokens.padding.medium * 2));
        }
        cellHeight: 48 * Tokens.scale

        // Counting characters is not the same as measuring them: a kaomoji
        // built from box drawing is wider than a longer one made of narrow
        // ones. The longest few are measured and the widest of those wins.
        readonly property var candidates: {
            const long = [];
            for (const entry of grid.model)
                if (entry.c.length > 2)
                    long.push(entry.c);
            return long.sort((a, b) => b.length - a.length).slice(0, 8);
        }

        TextMetrics { id: m0; font: Tokens.font.body.small; text: grid.candidates[0] ?? "" }
        TextMetrics { id: m1; font: Tokens.font.body.small; text: grid.candidates[1] ?? "" }
        TextMetrics { id: m2; font: Tokens.font.body.small; text: grid.candidates[2] ?? "" }
        TextMetrics { id: m3; font: Tokens.font.body.small; text: grid.candidates[3] ?? "" }
        TextMetrics { id: m4; font: Tokens.font.body.small; text: grid.candidates[4] ?? "" }
        TextMetrics { id: m5; font: Tokens.font.body.small; text: grid.candidates[5] ?? "" }
        TextMetrics { id: m6; font: Tokens.font.body.small; text: grid.candidates[6] ?? "" }
        TextMetrics { id: m7; font: Tokens.font.body.small; text: grid.candidates[7] ?? "" }

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

    StyledTooltip {
        anchors.right: sidebar.left
        anchors.verticalCenter: sidebar.bottom
        anchors.verticalCenterOffset: -(sidebar.width / 2)
        anchors.rightMargin: Tokens.spacing.small

        z: 1
        shown: root.addHovered
        text: root.query.trim() ? Tr.tr("Add \"%1\"").arg(root.query.trim()) : Tr.tr("Type something to add it")
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
