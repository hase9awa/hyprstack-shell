pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell.Wayland
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.services

Item {
    id: root

    required property HyprlandToplevel client

    Layout.fillHeight: true

    StyledClippingRect {
        id: preview

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: label.top
        anchors.topMargin: Tokens.padding.large
        anchors.bottomMargin: Tokens.spacing.medium

        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.medium

        Loader {
            asynchronous: true
            anchors.centerIn: parent
            width: Math.max(0, parent.width - Tokens.padding.large * 2)
            active: !root.client

            sourceComponent: ColumnLayout {
                spacing: 0

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "web_asset_off"
                    color: Colours.palette.m3outline
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(3).build()
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    text: Tr.tr("No active client")
                    color: Colours.palette.m3outline
                    font: Tokens.font.body.builders.large.size(28).weight(Font.Medium).build()
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    text: Tr.tr("Try switching to a window")
                    color: Colours.palette.m3outline
                    font: Tokens.font.body.large
                }
            }
        }

        ScreencopyView {
            anchors.centerIn: parent

            captureSource: root.client?.wayland ?? null // qmllint disable unresolved-type
            live: root.visible && !!root.client

            constraintSize: Qt.size(Math.max(1, preview.width), Math.max(1, preview.height))
        }
    }

    StyledText {
        id: label

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.padding.large

        animate: true
        text: {
            const client = root.client;
            if (!client)
                return Tr.tr("No active client");

            const mon = client.monitor;
            // TRANSLATORS: %1 = window title, %2 = monitor name, %3/%4 = x/y position in pixels
            return Tr.tr("%1 on monitor %2 at %3, %4").arg(client.title).arg(mon.name).arg(client.lastIpcObject.at[0]).arg(client.lastIpcObject.at[1]);
        }
    }
}
