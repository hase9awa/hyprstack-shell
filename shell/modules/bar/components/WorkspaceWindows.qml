pragma ComponentBehavior: Bound

import QtQuick
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.services

Item {
    id: root

    required property var bar
    readonly property string label: Tr.tr("Workspace windows")
    readonly property bool opensOnHover: Config.bar.activeWindow.showOnHover && Config.bar.popouts.activeWindow
    readonly property bool opened: bar.popouts.hasCurrent && bar.popouts.currentName === "workspacewindows"

    function open(): void {
        if (opened)
            return;
        bar.popouts.currentName = "workspacewindows";
        bar.popouts.currentCenter = Qt.binding(() => root.parent.x + root.width / 2);
        bar.popouts.hasCurrent = true;
    }

    function toggle(): void {
        if (opened)
            bar.popouts.close();
        else
            open();
    }

    implicitWidth: Math.min(bar.taskbarWidth, row.implicitWidth + Tokens.padding.medium * 2)
    implicitHeight: bar.height
    clip: true

    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: toggle()

    HoverHandler { cursorShape: Qt.PointingHandCursor }

    TapHandler {
        onTapped: root.toggle()
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: Tokens.spacing.small

        MaterialIcon {
            id: icon

            anchors.verticalCenter: parent.verticalCenter
            text: "view_list"
            color: Colours.palette.m3primary
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: !Config.bar.activeWindow.compact
                && icon.implicitWidth + implicitWidth + row.spacing + Tokens.padding.medium * 2 <= root.bar.taskbarWidth
            text: root.label
            color: Colours.palette.m3primary
            font: Tokens.font.body.small
        }
    }
}
