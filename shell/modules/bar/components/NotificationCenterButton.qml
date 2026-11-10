import QtQuick
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.services

Item {
    id: root

    required property ScreenState screenState

    implicitWidth: icon.implicitHeight + Tokens.padding.small
    implicitHeight: icon.implicitHeight
    Accessible.role: Accessible.Button
    Accessible.name: Tr.tr("Notification center")
    Accessible.description: Tr.tr("Unread notifications: %1").arg(Notifs.unreadCount)

    StateLayer {
        anchors.fill: undefined
        anchors.centerIn: parent
        implicitWidth: implicitHeight
        implicitHeight: icon.implicitHeight + Tokens.padding.small
        radius: Tokens.rounding.full
        onClicked: ShellState.setNotificationCenter(root.screenState, !root.screenState.sidebar)
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        text: Notifs.dnd ? "notifications_paused" : "notifications"
        color: root.screenState.sidebar || Notifs.unreadCount > 0 ? Colours.palette.m3primary : Colours.palette.m3secondary
        fontStyle: Tokens.font.icon.builders.small.weight(Font.Bold).build()
        fill: root.screenState.sidebar || Notifs.unreadCount > 0 ? 1 : 0
    }

    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: -4
        anchors.topMargin: -5
        visible: Notifs.unreadCount > 0
        width: Math.max(13, badge.implicitWidth + 5)
        height: 13 * Tokens.scale
        radius: 7 * Tokens.scale
        color: Colours.palette.m3primary

        Text {
            id: badge
            anchors.centerIn: parent
            text: Notifs.unreadCount > 99 ? "99+" : Notifs.unreadCount
            color: Colours.palette.m3onPrimary
            font.pixelSize: 9
            font.bold: true
        }
    }
}
