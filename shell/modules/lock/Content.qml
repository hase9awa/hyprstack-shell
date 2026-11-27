import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import qs.components
import qs.services

GridLayout {
    id: root

    required property var lock
    required property real preferredHeight

    readonly property bool portrait: width < preferredHeight
    readonly property bool showCards: width >= 640 * Tokens.scale && preferredHeight >= (portrait ? 760 : 400) * Tokens.scale
    readonly property real cardHeight: portrait ? preferredHeight * 0.45 : preferredHeight

    columns: showCards ? (portrait ? 2 : 3) : 1
    columnSpacing: Tokens.spacing.largeIncreased * 2
    rowSpacing: Tokens.spacing.largeIncreased

    ColumnLayout {
        visible: root.showCards
        Layout.row: root.portrait ? 1 : 0
        Layout.column: 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Tokens.spacing.medium

        WeatherInfo {
            Layout.fillWidth: true
            rootHeight: root.cardHeight
        }

        Fetch {
            Layout.fillWidth: true
            rootHeight: root.cardHeight
        }

        Media {
            Layout.fillWidth: true
            Layout.fillHeight: true
            lock: root.lock
        }
    }

    Center {
        Layout.row: 0
        Layout.column: root.showCards && !root.portrait ? 1 : 0
        Layout.columnSpan: root.showCards && root.portrait ? 2 : 1
        Layout.fillHeight: !root.showCards || !root.portrait
        Layout.alignment: Qt.AlignHCenter

        lock: root.lock
        centerScale: Math.min(1, (lock.screen?.height ?? 1440) / 1440,
            root.width * (root.showCards && !root.portrait ? 0.52 : 1) / Tokens.sizes.lock.centerWidth,
            root.preferredHeight * (root.showCards && root.portrait ? 0.6 : 1) / Tokens.sizes.lock.centerWidth)
    }

    ColumnLayout {
        visible: root.showCards
        Layout.row: root.portrait ? 1 : 0
        Layout.column: root.portrait ? 1 : 2
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Tokens.spacing.medium

        Resources {
            Layout.fillWidth: true
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true

            bottomRightRadius: Tokens.rounding.extraLarge
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainer

            NotifDock {
                lock: root.lock
            }
        }
    }
}
