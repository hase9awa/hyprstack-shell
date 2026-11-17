pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root
    objectName: "notificationQuickActions"

    required property PopoutState popouts
    implicitWidth: 300 * Tokens.scale
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.small

        StyledText {
            text: Tr.tr("Notifications")
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
        }

        StyledText {
            text: Tr.tr("Unread notifications: %1").arg(Notifs.unreadCount)
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            spacing: Tokens.spacing.medium

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("Do not disturb")
            }
            StyledSwitch {
                objectName: "notificationQuickDnd"
                checked: Notifs.dnd
                onToggled: Notifs.dnd = checked
            }
        }

        IconTextButton {
            objectName: "notificationQuickRead"
            Layout.fillWidth: true
            disabled: Notifs.unreadCount === 0
            icon: "done_all"
            text: Tr.tr("Mark all as read")
            onClicked: Notifs.markAllRead()
        }

        IconTextButton {
            objectName: "notificationQuickClear"
            Layout.fillWidth: true
            disabled: Notifs.notClosed.length === 0
            icon: "delete_sweep"
            text: Tr.tr("Clear all")
            onClicked: Notifs.clearAll()
        }

        IconTextButton {
            objectName: "notificationQuickOpen"
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            inactiveColour: Colours.palette.m3primaryContainer
            inactiveOnColour: Colours.palette.m3onPrimaryContainer
            verticalPadding: Tokens.padding.extraSmall
            text: Tr.tr("Open notification center")
            icon: "notifications"
            onClicked: {
                root.popouts.hasCurrent = false;
                ShellState.setNotificationCenter(ShellState.forScreen(root.popouts.screen), true);
            }
        }
    }
}
