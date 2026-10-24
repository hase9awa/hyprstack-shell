import QtQuick
import QtQuick.Controls
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.services

Item {
    id: root

    readonly property bool connected: VPN.connected && VPN.status.state !== "error" && VPN.status.state !== "needs-auth"
    readonly property bool busy: VPN.connecting || VPN.disconnecting || (VPN.active.name === "native" && ManagedVPN.busy)
    readonly property string statusText: busy ? Tr.tr("Updating connection…") : connected ? Tr.tr("VPN connected") : Tr.tr("VPN disconnected")
    readonly property color foreground: connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant

    implicitWidth: icon.implicitHeight + Tokens.padding.small
    implicitHeight: icon.implicitHeight
    activeFocusOnTab: !busy
    Accessible.role: Accessible.CheckBox
    Accessible.name: Tr.tr("VPN")
    Accessible.description: statusText
    Accessible.checkable: true
    Accessible.checked: connected
    Accessible.onToggleAction: root.toggle()

    function toggle(): void {
        if (busy)
            return;
        if (VPN.active.name === "native" && ManagedVPN.profiles.length === 0)
            ManagedVPN.openSettings();
        else
            VPN.toggle();
    }

    Keys.onSpacePressed: root.toggle()
    Keys.onReturnPressed: root.toggle()

    StateLayer {
        id: hitArea
        anchors.fill: undefined
        anchors.centerIn: parent
        implicitWidth: root.implicitWidth
        implicitHeight: root.implicitHeight + Tokens.padding.small
        radius: Tokens.rounding.full
        disabled: root.busy
        manualHoverOverride: root.activeFocus
        onClicked: root.toggle()
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

    ToolTip.visible: hitArea.containsMouse || root.activeFocus
    ToolTip.text: root.statusText
    ToolTip.delay: 400
}
