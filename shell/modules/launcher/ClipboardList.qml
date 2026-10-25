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

StyledListView {
    id: root

    required property SearchBar search
    required property ScreenState screenState

    // The history is read once the list appears rather than kept in sync:
    // nothing else in the shell needs it.
    Component.onCompleted: Clipboard.refresh()

    model: ScriptModel {
        readonly property string query: root.search.text.split(" ").slice(1).join(" ").toLowerCase()

        values: Clipboard.entries.filter(entry => !query || entry.label.toLowerCase().includes(query))
        onValuesChanged: root.currentIndex = 0
    }

    spacing: Tokens.spacing.small
    orientation: Qt.Vertical
    implicitHeight: (Tokens.sizes.launcher.clipHeight + spacing) * Math.min(Config.launcher.maxShown, count)
        - spacing + (footerItem?.implicitHeight ?? 0)

    preferredHighlightBegin: 0
    preferredHighlightEnd: height
    highlightRangeMode: ListView.ApplyRange

    highlightFollowsCurrentItem: false
    highlight: StyledRect {
        radius: Tokens.rounding.large
        color: Colours.palette.m3onSurface
        opacity: 0.08

        y: root.currentItem?.y ?? 0
        implicitWidth: root.width
        implicitHeight: root.currentItem?.implicitHeight ?? 0

        Behavior on y {
            Anim {}
        }
    }

    delegate: ClipItem {
        list: root
        screenState: root.screenState
    }

    // Emptying the history is a sweeping action, so it stays in view rather
    // than waiting at the end of a long list.
    footerPositioning: ListView.OverlayFooter
    footer: StyledRect {
        z: 2
        implicitWidth: root.width
        implicitHeight: clearRow.implicitHeight + Tokens.padding.small * 2
        color: Colours.palette.m3surfaceContainer

        Row {
            id: clearRow

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            IconTextButton {
                type: IconTextButton.Tonal
                verticalPadding: Tokens.padding.extraSmall
                icon: "delete_sweep"
                text: Tr.tr("Clear history")
                // Pinned entries live in the shell's own storage and stay.
                disabled: Clipboard.history.length === 0
                onClicked: Clipboard.clear()
            }
        }
    }

    StyledScrollBar.vertical: StyledScrollBar {
        flickable: root
    }
}
