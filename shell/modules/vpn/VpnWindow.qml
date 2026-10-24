pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.services

FloatingWindow {
    id: root

    objectName: "vpnSettingsWindow"
    title: Tr.tr("VPN settings")
    color: Colours.tPalette.m3surface
    implicitWidth: 700
    implicitHeight: 700
    minimumSize.width: 520
    minimumSize.height: 460
    visible: true
    contentItem.Config.screen: screen.name
    contentItem.Tokens.screen: screen.name

    readonly property var selected: ManagedVPN.profiles.find(p => p.id === ManagedVPN.data.selectedProfile) ?? null
    readonly property bool working: ManagedVPN.busy || VPN.connecting || VPN.disconnecting

    onVisibleChanged: {
        if (!visible) {
            ManagedVPN.window = null;
            destroy();
        }
    }

    Connections {
        target: ManagedVPN
        function onOperationFinished(command: string, success: bool): void {
            if (command === "import" && success)
                linkInput.text = "";
        }
    }

    RowLayout {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        MaterialIcon {
            text: VPN.connected ? "vpn_key" : "vpn_key_off"
            fontStyle: Tokens.font.icon.large
            color: VPN.connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall
            StyledText {
                text: Tr.tr("VPN")
                font: Tokens.font.headline.small
            }
            StyledText {
                Layout.fillWidth: true
                text: root.working ? Tr.tr("Updating connection…") : VPN.connected ? Tr.trCtx("Connected", "vpn state") : Tr.tr("Disconnected")
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.Wrap
            }
        }

        BusyIndicator {
            visible: root.working
            running: visible
            implicitWidth: 28
            implicitHeight: 28
        }

        IconTextButton {
            objectName: "vpnConnectButton"
            icon: VPN.connected ? "power_settings_new" : "vpn_key"
            text: VPN.connected ? Tr.tr("Disconnect") : Tr.tr("Connect")
            disabled: root.working || (!VPN.connected && !root.selected)
            onClicked: VPN.toggle()
        }

        IconButton {
            objectName: "vpnCloseButton"
            type: IconButton.Text
            icon: "close"
            Accessible.name: Tr.tr("Close window")
            ToolTip.visible: hovered
            ToolTip.text: Tr.tr("Close window")
            onClicked: root.visible = false
        }
    }

    ScrollView {
        objectName: "vpnScrollView"
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: Tokens.spacing.medium
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: Tokens.spacing.medium

            StyledText {
                objectName: "vpnError"
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.padding.large
                Layout.rightMargin: Tokens.padding.large
                visible: ManagedVPN.error.length > 0
                text: ManagedVPN.error
                color: Colours.palette.m3error
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.padding.large
                Layout.rightMargin: Tokens.padding.large
                spacing: Tokens.spacing.small

                IconTextButton {
                    objectName: "vpnInstallButton"
                    visible: ManagedVPN.data.installed === false
                    disabled: root.working
                    icon: "download"
                    text: Tr.tr("Install background VPN engine")
                    onClicked: ManagedVPN.run("install", {})
                }

                StyledText { text: Tr.tr("Connection profile"); font: Tokens.font.title.small }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    Choice {
                        objectName: "vpnProfileChoice"
                        Layout.fillWidth: true
                        model: ManagedVPN.profiles
                        textRole: "name"
                        valueRole: "id"
                        currentIndex: ManagedVPN.profiles.findIndex(p => p.id === ManagedVPN.data.selectedProfile)
                        enabled: !root.working && count > 0
                        displayText: count > 0 ? currentText : Tr.tr("Add a profile below")
                        onActivated: index => ManagedVPN.run("select", {id: ManagedVPN.profiles[index].id})
                    }
                    IconButton {
                        icon: "network_ping"
                        disabled: root.working || !root.selected
                        onClicked: ManagedVPN.run("test", {id: root.selected.id})
                        ToolTip.visible: hovered
                        ToolTip.text: Tr.tr("Test latency")
                    }
                    IconButton {
                        icon: "delete"
                        disabled: root.working || VPN.connected || !root.selected
                        onClicked: deleteDialog.open()
                        ToolTip.visible: hovered
                        ToolTip.text: Tr.tr("Delete profile")
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.selected ? `${root.selected.type.toUpperCase()}${root.selected.latency_ms > 0 ? ` · ${root.selected.latency_ms} ms` : ""}` : Tr.tr("No profiles configured")
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.Wrap
                }

                StyledText { text: Tr.tr("Connection mode"); font: Tokens.font.title.small }
                Choice {
                    objectName: "vpnModeChoice"
                    Layout.fillWidth: true
                    model: [{name: Tr.tr("VPN · all applications"), value: "tun"}, {name: Tr.tr("Local proxy · selected applications"), value: "proxy"}]
                    textRole: "name"
                    valueRole: "value"
                    currentIndex: ManagedVPN.data.mode === "proxy" ? 1 : 0
                    enabled: !root.working
                    onActivated: index => ManagedVPN.run("mode", {mode: index === 0 ? "tun" : "proxy"})
                }
                StyledText {
                    Layout.fillWidth: true
                    text: ManagedVPN.data.mode === "proxy" ? Tr.tr("SOCKS5: 127.0.0.1:2080 · HTTP: 127.0.0.1:2081") : Tr.tr("Traffic is routed through a VPN tunnel, including applications without proxy settings.")
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.Wrap
                }

                IconTextButton {
                    objectName: "vpnAuthorizeButton"
                    visible: ManagedVPN.data.mode === "tun" && !ManagedVPN.data.canTun
                    disabled: root.working
                    icon: "admin_panel_settings"
                    text: Tr.tr("Authorize VPN tunnel")
                    onClicked: ManagedVPN.run("authorize", {})
                }

                StyledText { text: Tr.tr("Routing profile"); font: Tokens.font.title.small }
                Choice {
                    objectName: "vpnRouteChoice"
                    Layout.fillWidth: true
                    model: ManagedVPN.routes.map(route => Object.assign({}, route, {name: Tr.tr(route.name)}))
                    textRole: "name"
                    valueRole: "id"
                    currentIndex: ManagedVPN.routes.findIndex(route => route.active)
                    enabled: !root.working && count > 0
                    onActivated: index => ManagedVPN.run("route", {id: ManagedVPN.routes[index].id})
                }

                RowLayout {
                    Layout.fillWidth: true
                    StyledText { Layout.fillWidth: true; text: Tr.tr("Reconnect after login") }
                    StyledSwitch {
                        checked: GlobalConfig.utilities.vpn.enabled
                        enabled: !root.working
                        onToggled: GlobalConfig.utilities.vpn.enabled = checked
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.medium
                    text: Tr.tr("Add profiles or a subscription")
                    font: Tokens.font.title.small
                    wrapMode: Text.Wrap
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "VLESS · Trojan · VMess · Shadowsocks · Hysteria2 · TUIC · SOCKS · HTTP"
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.Wrap
                }

                Choice {
                    id: importType
                    Layout.fillWidth: true
                    model: [Tr.tr("Profile links or configuration"), Tr.tr("Subscription URL")]
                    enabled: !root.working
                }

                StyledTextField {
                    id: subscriptionName
                    Layout.fillWidth: true
                    visible: importType.currentIndex === 1
                    placeholderText: Tr.tr("Subscription name")
                    enabled: !root.working
                }

                TextArea {
                    id: linkInput
                    objectName: "vpnImportInput"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 108 * Tokens.scale
                    enabled: !root.working
                    selectByMouse: true
                    wrapMode: TextEdit.WrapAnywhere
                    textFormat: TextEdit.PlainText
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    color: Colours.palette.m3onSurface
                    placeholderText: importType.currentIndex === 1 ? "https://…" : "vless://…\ntrojan://…"
                    placeholderTextColor: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    padding: Tokens.padding.medium
                    background: StyledRect { color: Colours.tPalette.m3surfaceContainer; radius: Tokens.rounding.small }
                }

                RowLayout {
                    Layout.fillWidth: true
                    IconTextButton {
                        objectName: "vpnImportButton"
                        icon: "add_link"
                        text: Tr.tr("Import")
                        disabled: root.working || linkInput.text.trim().length === 0
                        onClicked: ManagedVPN.run("import", {text: linkInput.text, subscription: importType.currentIndex === 1, name: subscriptionName.text})
                    }
                    IconTextButton {
                        icon: "sync"
                        text: Tr.tr("Update subscriptions")
                        disabled: root.working
                        onClicked: ManagedVPN.run("update", {})
                    }
                    Item { Layout.fillWidth: true }
                    IconButton {
                        icon: "refresh"
                        disabled: root.working
                        onClicked: ManagedVPN.refresh()
                    }
                }
            }

            Item { Layout.preferredHeight: Tokens.padding.large }
        }
    }

    Dialog {
        id: deleteDialog
        anchors.centerIn: parent
        modal: true
        title: Tr.tr("Delete profile?")
        standardButtons: Dialog.Yes | Dialog.No
        onAccepted: if (root.selected) ManagedVPN.run("delete", {id: root.selected.id})
    }

    component Choice: ComboBox {
        font: Tokens.font.body.small
        implicitHeight: 44 * Tokens.scale
        palette.buttonText: Colours.palette.m3onSurface
        palette.text: Colours.palette.m3onSurface
        palette.window: Colours.tPalette.m3surfaceContainer
        palette.base: Colours.tPalette.m3surfaceContainer
        palette.highlight: Colours.palette.m3primaryContainer
        palette.highlightedText: Colours.palette.m3onPrimaryContainer
        background: StyledRect {
            color: Colours.tPalette.m3surfaceContainer
            radius: Tokens.rounding.small
        }
    }
}
