pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.misc
import qs.services

StyledRect {
    id: root

    readonly property color colour: Colours.palette.m3tertiary
    required property ScreenState screenState
    readonly property int padding: Config.bar.clock.background ? Tokens.padding.medium : Tokens.padding.extraSmall

    implicitWidth: layout.implicitWidth + padding * 2
    implicitHeight: Tokens.sizes.bar.innerWidth
    color: "transparent"
    radius: Tokens.rounding.full

    Ref { service: root.visible && root.Config.bar.clock.showSeconds ? Time : null }

    GroupBackground {
        color: Qt.alpha(Colours.tPalette.m3surfaceContainer, Config.bar.clock.background ? Colours.tPalette.m3surfaceContainer.a : 0)
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.screenState.dashboard = !root.screenState.dashboard
    }

    RowLayout {
        id: layout

        anchors.centerIn: parent
        spacing: Tokens.spacing.small

        Loader {
            Layout.alignment: Qt.AlignVCenter
            asynchronous: true
            active: Config.bar.clock.showIcon
            visible: active

            sourceComponent: MaterialIcon {
                text: "calendar_month"
                color: root.colour
            }
        }

        Loader {
            Layout.alignment: Qt.AlignVCenter
            asynchronous: true
            active: Config.bar.clock.showDate
            visible: active

            sourceComponent: StyledText {
                text: Time.format("ddd d")
                font: Tokens.font.body.builders.small.scale(0.9).build()
                color: root.colour
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: `${Time.hourStr}:${Time.minuteStr}${root.Config.bar.clock.showSeconds ? ":" + Time.format("ss") : ""}${Units.twelveHourClock ? " " + Time.amPmStr.toLowerCase() : ""}`
            font: Tokens.font.body.builders.small.scale(1.1).build()
            color: root.colour
        }
    }
}
