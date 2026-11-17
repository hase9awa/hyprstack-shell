import QtQuick
import QtQuick.Controls
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.services

Item {
    id: root
    property ScreenState screenState

    readonly property bool connected: VPN.connected && VPN.status.state !== "error" && VPN.status.state !== "needs-auth"
    readonly property bool busy: VPN.connecting || VPN.disconnecting || (VPN.active.name === "native" && ManagedVPN.busy)
    readonly property string statusText: busy ? Tr.tr("Updating connection…") : connected ? Tr.tr("VPN connected") : Tr.tr("VPN disconnected")
    readonly property color foreground: connected ? Colours.palette.m3primary : Colours.palette.m3secondary

    implicitWidth: icon.implicitHeight + Tokens.padding.small
    implicitHeight: icon.implicitHeight
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: Tr.tr("VPN")
    Accessible.description: statusText
    Accessible.onPressAction: root.activate()

    function activate(): void {
        if (screenState)
            ShellState.componentsFor(screenState.modelData)?.panels?.popouts.close();
        ManagedVPN.openSettings();
    }

    Keys.onSpacePressed: root.activate()
    Keys.onReturnPressed: root.activate()

    StateLayer {
        id: hitArea
        anchors.fill: undefined
        anchors.centerIn: parent
        implicitWidth: root.implicitWidth
        implicitHeight: root.implicitHeight + Tokens.padding.small
        radius: Tokens.rounding.full
        manualHoverOverride: root.activeFocus
        onClicked: root.activate()
    }

    MaterialIcon {
        id: icon
        anchors.centerIn: parent
        text: "shield_lock"
        color: root.foreground
        fontStyle: Tokens.font.icon.builders.small.weight(Font.Bold).build()
        fill: root.connected ? 1 : 0
        opacity: root.busy ? 0.5 : 1
    }

    ToolTip.visible: (hitArea.containsMouse && !Config.bar.popouts.vpn) || root.activeFocus
    ToolTip.text: root.statusText + "\n" + Tr.tr("Open settings")
    ToolTip.delay: 400
}
