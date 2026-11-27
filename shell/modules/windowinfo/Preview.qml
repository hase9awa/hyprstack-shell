pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Hyprstack.Config
import qs.components
import qs.components.widgets
import qs.services

StyledClippingRect {
    id: root
    objectName: "windowInfoPreview"

    required property ShellScreen screen
    required property HyprlandToplevel client

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.large

    WindowCapture {
        id: capture
        objectName: "windowCapture"

        anchors.fill: parent
        anchors.margins: Tokens.padding.small
        screen: root.screen
        client: root.client
    }

    MaterialIcon {
        anchors.centerIn: parent
        visible: !capture.hasFrame
        text: "web_asset_off"
        color: Colours.palette.m3outline
        fontStyle: Tokens.font.icon.extraLarge
    }
}
