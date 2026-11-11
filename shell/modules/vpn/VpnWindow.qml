pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.modules.nexus.common
import qs.services
import "../../utils/scripts/vpn-flow.js" as Flow

FloatingWindow {
    id: root

    property bool advancedOpen: false
    readonly property bool connected: ManagedVPN.connected
    readonly property string connectionHint: {
        if (working)
            return "";
        if (otherConnected)
            return Tr.tr("%1 is connected. Disconnect it before using this VPN.").arg(VPN.active.displayName);
        if (connected)
            return ManagedVPN.data.mode === "proxy" ? Tr.tr("Local proxy · selected applications") : Tr.tr("VPN · all applications");
        if (!ManagedVPN.profiles.length)
            return Tr.tr("Add a server link or subscription to get started.");
        if (primaryAction === "install")
            return Tr.tr("Prepare the VPN components once, then connect.");
        if (primaryAction === "authorize")
            return Tr.tr("Allow access to create a VPN tunnel. A system prompt will appear.");
        return Tr.tr("Choose a server, then press Connect.");
    }
    readonly property string connectionText: {
        if (working) {
            switch (ManagedVPN.action) {
            case "import":
                return Tr.tr("Adding connection…");
            case "install":
                return Tr.tr("Preparing VPN…");
            case "authorize":
                return Tr.tr("Waiting for permission…");
            case "test":
                return Tr.tr("Testing latency…");
            case "update":
                return Tr.tr("Updating subscriptions…");
            default:
                return Tr.tr("Updating connection…");
            }
        }
        if (connected)
            return Tr.tr("Connected to %1").arg(ManagedVPN.data.server || selected?.name || Tr.tr("VPN"));
        return Tr.tr("Disconnected");
    }
    property var deleteTarget: null
    readonly property bool otherConnected: VPN.connected && VPN.active.name !== "native"
    readonly property string primaryAction: Flow.primaryAction({
        busy: working,
        connected: connected,
        otherConnected: otherConnected,
        hasProfile: !!selected,
        profileCount: ManagedVPN.profiles.length,
        installed: ManagedVPN.data.installed,
        mode: ManagedVPN.data.mode,
        canTun: ManagedVPN.data.canTun
    })
    readonly property string primaryText: {
        switch (primaryAction) {
        case "busy":
            return Tr.tr("Please wait…");
        case "disconnect":
            return Tr.tr("Disconnect");
        case "disconnect-other":
            return Tr.tr("Disconnect other VPN");
        case "import":
            return Tr.tr("Add connection");
        case "select":
            return Tr.tr("Select a server");
        case "install":
            return Tr.tr("Prepare VPN");
        case "authorize":
            return Tr.tr("Allow VPN");
        default:
            return Tr.tr("Connect");
        }
    }
    readonly property var selected: ManagedVPN.selectedProfile
    readonly property bool working: ManagedVPN.busy || VPN.connecting || VPN.disconnecting

    function activatePrimary(): void {
        switch (primaryAction) {
        case "disconnect":
            ManagedVPN.run("disconnect", {});
            break;
        case "disconnect-other":
            VPN.disconnect();
            break;
        case "import":
            addConnection();
            break;
        case "select":
            profileList.itemAt(0)?.forceActiveFocus();
            break;
        case "install":
            ManagedVPN.run("install", {});
            break;
        case "authorize":
            ManagedVPN.run("authorize", {});
            break;
        case "connect":
            ManagedVPN.connectSelected();
            break;
        }
    }
    function addConnection(): void {
        ManagedVPN.error = "";
        importDialog.open();
        Qt.callLater(() => linkInput.forceActiveFocus());
    }
    function selectProfile(id: var): void {
        if (!working && selected?.id !== id)
            ManagedVPN.run("select", {
                id: id
            });
    }

    color: Colours.palette.m3surface
    contentItem.Config.screen: screen.name
    contentItem.Tokens.screen: screen.name
    implicitHeight: 660
    implicitWidth: 740
    minimumSize.height: 480
    minimumSize.width: 560
    objectName: "vpnSettingsWindow"
    title: Tr.tr("VPN")
    visible: true

    onVisibleChanged: {
        if (!visible) {
            ManagedVPN.window = null;
            destroy();
        }
    }

    Connections {
        function onOperationFinished(command: string, success: bool): void {
            if (command === "import" && success) {
                importDialog.close();
                linkInput.clear();
                subscriptionName.text = "";
            }
        }

        target: ManagedVPN
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                font: Tokens.font.headline.small
                text: Tr.tr("VPN")
            }
            IconButton {
                Accessible.name: Tr.tr("Close window")
                ToolTip.text: Tr.tr("Close window")
                ToolTip.visible: hovered
                icon: "close"
                objectName: "vpnCloseButton"
                type: IconButton.Text

                onClicked: root.visible = false
            }
        }
        ScrollView {
            id: scroll

            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true
            contentWidth: availableWidth
            objectName: "vpnScrollView"

            ColumnLayout {
                spacing: Tokens.spacing.medium
                width: scroll.availableWidth

                ConnectedRect {
                    Layout.fillWidth: true
                    first: true
                    implicitHeight: connection.implicitHeight + Tokens.padding.large * 2
                    last: true
                    objectName: "vpnConnectionCard"

                    RowLayout {
                        id: connection

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.large
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            color: root.connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            fill: root.connected ? 1 : 0
                            fontStyle: Tokens.font.icon.large
                            text: root.connected ? "shield_lock" : "shield"
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: Tokens.spacing.extraSmall

                            StyledText {
                                Layout.fillWidth: true
                                font: Tokens.font.title.small
                                objectName: "vpnConnectionStatus"
                                text: root.connectionText
                                textFormat: Text.PlainText
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            }
                            StyledText {
                                Layout.fillWidth: true
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
                                text: root.connectionHint
                                textFormat: Text.PlainText
                                visible: !!text
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            }
                        }
                        BusyIndicator {
                            implicitHeight: 28
                            implicitWidth: 28
                            running: visible
                            visible: root.working
                        }
                        IconTextButton {
                            disabled: root.working
                            icon: root.connected || root.otherConnected ? "power_settings_new" : root.primaryAction === "import" ? "add" : "vpn_key"
                            objectName: "vpnConnectButton"
                            text: root.primaryText
                            type: root.connected ? IconTextButton.Tonal : IconTextButton.Filled

                            onClicked: root.activatePrimary()
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    color: Colours.palette.m3error
                    objectName: "vpnError"
                    text: ManagedVPN.error
                    textFormat: Text.PlainText
                    visible: !!ManagedVPN.error && !importDialog.opened
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall / 2
                    visible: ManagedVPN.profiles.length > 0

                    RowLayout {
                        Layout.bottomMargin: Tokens.spacing.small
                        Layout.fillWidth: true

                        StyledText {
                            Layout.fillWidth: true
                            font: Tokens.font.title.small
                            text: Tr.tr("Servers")
                        }
                        IconTextButton {
                            disabled: root.working
                            icon: "add"
                            objectName: "vpnAddConnectionButton"
                            text: Tr.tr("Add connection")
                            type: IconTextButton.Tonal

                            onClicked: root.addConnection()
                        }
                    }
                    Repeater {
                        id: profileList

                        model: ManagedVPN.profiles

                        delegate: RowButton {
                            required property int index
                            required property var modelData
                            readonly property bool selected: modelData.id === ManagedVPN.data.selectedProfile

                            Accessible.checkable: true
                            Accessible.checked: selected
                            Accessible.name: modelData.name
                            Accessible.role: Accessible.RadioButton
                            activeFocusOnTab: !disabled
                            color: selected ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
                            border.width: activeFocus ? 2 * Tokens.scale : 0
                            border.color: Colours.palette.m3primary
                            disabled: root.working
                            first: index === 0
                            icon: selected ? "radio_button_checked" : "radio_button_unchecked"
                            label.textFormat: Text.PlainText
                            last: index === ManagedVPN.profiles.length - 1
                            objectName: "vpnProfile_" + modelData.id
                            subLabel.color: Colours.palette.m3onSurfaceVariant
                            subtext: modelData.type.toUpperCase() + (modelData.latency_ms > 0 ? " · " + Tr.tr("%1 ms").arg(modelData.latency_ms) : "")
                            text: modelData.name
                            trailingIcon: selected && root.connected ? "vpn_key" : selected ? "check" : ""

                            Accessible.onPressAction: root.selectProfile(modelData.id)
                            Keys.onReturnPressed: root.selectProfile(modelData.id)
                            Keys.onSpacePressed: root.selectProfile(modelData.id)
                            onClicked: root.selectProfile(modelData.id)
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                        text: Tr.tr("Choosing another server reconnects the VPN.")
                        visible: root.connected && ManagedVPN.profiles.length > 1
                        wrapMode: Text.Wrap
                    }
                    RowLayout {
                        Layout.topMargin: Tokens.spacing.small

                        IconTextButton {
                            disabled: root.working || !root.selected
                            icon: "network_ping"
                            objectName: "vpnTestButton"
                            text: Tr.tr("Test latency")
                            type: IconTextButton.Text

                            onClicked: ManagedVPN.run("test", {
                                id: root.selected.id
                            })
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        IconTextButton {
                            disabled: root.working || root.connected || !root.selected
                            icon: "delete"
                            objectName: "vpnDeleteButton"
                            text: Tr.tr("Delete profile")
                            type: IconTextButton.Text

                            onClicked: {
                                root.deleteTarget = {
                                    id: root.selected.id,
                                    name: root.selected.name
                                };
                                deleteDialog.open();
                            }
                        }
                    }
                }
                RowButton {
                    first: true
                    icon: "tune"
                    last: true
                    objectName: "vpnAdvancedButton"
                    text: Tr.tr("Advanced")
                    trailingIcon: root.advancedOpen ? "expand_less" : "expand_more"

                    onClicked: root.advancedOpen = !root.advancedOpen
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    visible: root.advancedOpen

                    StyledText {
                        Layout.fillWidth: true
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        text: Tr.tr("Disconnect to change connection settings.")
                        visible: root.connected
                        wrapMode: Text.Wrap
                    }
                    StyledText {
                        font: Tokens.font.title.small
                        text: Tr.tr("Connection mode")
                    }
                    Choice {
                        Layout.fillWidth: true
                        currentIndex: ManagedVPN.data.mode === "proxy" ? 1 : 0
                        enabled: !root.working && !root.connected
                        model: [
                            {
                                name: Tr.tr("VPN · all applications"),
                                value: "tun"
                            },
                            {
                                name: Tr.tr("Local proxy · selected applications"),
                                value: "proxy"
                            }
                        ]
                        objectName: "vpnModeChoice"
                        textRole: "name"
                        valueRole: "value"

                        onActivated: index => ManagedVPN.run("mode", {
                                mode: index === 0 ? "tun" : "proxy"
                            })
                    }
                    StyledText {
                        Layout.fillWidth: true
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        text: Tr.tr("SOCKS5: 127.0.0.1:2080 · HTTP: 127.0.0.1:2081")
                        visible: ManagedVPN.data.mode === "proxy"
                        wrapMode: Text.Wrap
                    }
                    StyledText {
                        font: Tokens.font.title.small
                        text: Tr.tr("Routing profile")
                    }
                    Choice {
                        Layout.fillWidth: true
                        currentIndex: ManagedVPN.routes.findIndex(route => route.active)
                        enabled: !root.working && !root.connected && count > 0
                        model: ManagedVPN.routes.map(route => Object.assign({}, route, {
                                name: Tr.tr(route.name)
                            }))
                        objectName: "vpnRouteChoice"
                        textRole: "name"
                        valueRole: "id"

                        onActivated: index => ManagedVPN.run("route", {
                                id: ManagedVPN.routes[index].id
                            })
                    }
                    ToggleRow {
                        checked: GlobalConfig.utilities.vpn.enabled
                        disabled: root.working || root.otherConnected
                        first: true
                        last: true
                        text: Tr.tr("Reconnect after login")

                        onToggled: {
                            if (!checked || VPN.selectManagedProvider())
                                GlobalConfig.utilities.vpn.enabled = checked;
                        }
                    }
                    IconTextButton {
                        disabled: root.working || root.connected
                        icon: "sync"
                        objectName: "vpnUpdateSubscriptionsButton"
                        text: Tr.tr("Update subscriptions")
                        type: IconTextButton.Tonal
                        visible: (ManagedVPN.data.groups ?? []).some(group => group.subscription)

                        onClicked: ManagedVPN.run("update", {})
                    }
                }
                Item {
                    Layout.preferredHeight: Tokens.padding.small
                }
            }
        }
    }
    Dialog {
        id: importDialog

        anchors.centerIn: parent
        closePolicy: root.working ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
        footer: null
        header: null
        height: Math.min(implicitHeight, root.height - 32)
        implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
        modal: true
        objectName: "vpnImportDialog"
        padding: root.contentItem.Tokens.padding.large
        parent: Overlay.overlay
        width: Math.min(root.width - 40, 560 * root.contentItem.Tokens.scale)

        background: StyledRect {
            color: Colours.palette.m3surfaceContainerHigh
            radius: root.contentItem.Tokens.rounding.large
        }
        contentItem: ColumnLayout {
            spacing: root.contentItem.Tokens.spacing.medium

            StyledText {
                Layout.fillWidth: true
                font: root.contentItem.Tokens.font.title.medium
                text: Tr.tr("Add connection")
            }
            ScrollView {
                id: importScroll

                Layout.fillHeight: true
                Layout.fillWidth: true
                clip: true
                contentWidth: availableWidth
                implicitHeight: importFields.implicitHeight
                objectName: "vpnImportScroll"

                ColumnLayout {
                    id: importFields

                    spacing: root.contentItem.Tokens.spacing.small
                    width: importScroll.availableWidth

                    Choice {
                        id: importType

                        Layout.fillWidth: true
                        enabled: !root.working
                        model: [Tr.tr("Profile links or configuration"), Tr.tr("Subscription URL")]
                        objectName: "vpnImportType"
                    }
                    StyledTextField {
                        id: subscriptionName

                        Layout.fillWidth: true
                        enabled: !root.working
                        placeholderText: Tr.tr("Subscription name")
                        visible: importType.currentIndex === 1
                    }
                    TextArea {
                        id: linkInput

                        Layout.fillWidth: true
                        Layout.minimumHeight: 64 * root.contentItem.Tokens.scale
                        Layout.preferredHeight: 130 * root.contentItem.Tokens.scale
                        color: Colours.palette.m3onSurface
                        enabled: !root.working
                        font: root.contentItem.Tokens.font.body.small
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        objectName: "vpnImportInput"
                        padding: root.contentItem.Tokens.padding.medium
                        placeholderText: importType.currentIndex === 1 ? "https://…" : "vless://…\ntrojan://…"
                        placeholderTextColor: Colours.palette.m3onSurfaceVariant
                        selectByMouse: true
                        textFormat: TextEdit.PlainText
                        wrapMode: TextEdit.WrapAnywhere

                        background: StyledRect {
                            color: Colours.palette.m3surfaceContainer
                            radius: root.contentItem.Tokens.rounding.small
                        }
                    }
                    TextButton {
                        Tokens.screen: root.contentItem.Tokens.screen
                        disabled: root.working
                        text: Tr.tr("Paste")
                        type: TextButton.Text

                        onClicked: {
                            linkInput.forceActiveFocus();
                            linkInput.paste();
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        color: Colours.palette.m3error
                        font: root.contentItem.Tokens.font.body.small
                        text: ManagedVPN.error
                        textFormat: Text.PlainText
                        visible: !!ManagedVPN.error
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: root.contentItem.Tokens.spacing.small

                Item {
                    Layout.fillWidth: true
                }
                TextButton {
                    Tokens.screen: root.contentItem.Tokens.screen
                    disabled: root.working
                    text: Tr.trCtx("Cancel", "button")
                    type: TextButton.Text

                    onClicked: importDialog.close()
                }
                TextButton {
                    Tokens.screen: root.contentItem.Tokens.screen
                    disabled: root.working || !linkInput.text.trim()
                    objectName: "vpnImportButton"
                    text: root.working ? Tr.tr("Adding connection…") : Tr.tr("Import")

                    onClicked: ManagedVPN.run("import", {
                        text: linkInput.text,
                        subscription: importType.currentIndex === 1,
                        name: subscriptionName.text
                    })
                }
            }
        }
    }
    Dialog {
        id: deleteDialog

        anchors.centerIn: parent
        footer: null
        header: null
        height: Math.min(implicitHeight, root.height - 32)
        implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
        modal: true
        objectName: "vpnDeleteDialog"
        padding: root.contentItem.Tokens.padding.large
        parent: Overlay.overlay
        width: Math.min(root.width - 40, 440 * root.contentItem.Tokens.scale)

        background: StyledRect {
            color: Colours.palette.m3surfaceContainerHigh
            radius: root.contentItem.Tokens.rounding.large
        }
        contentItem: ColumnLayout {
            spacing: root.contentItem.Tokens.spacing.medium

            StyledText {
                Layout.fillWidth: true
                font: root.contentItem.Tokens.font.title.medium
                text: Tr.tr("Delete profile?")
            }
            StyledText {
                Layout.fillWidth: true
                font: root.contentItem.Tokens.font.body.medium
                text: root.deleteTarget?.name ?? ""
                textFormat: Text.PlainText
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: root.contentItem.Tokens.spacing.small

                Item {
                    Layout.fillWidth: true
                }
                TextButton {
                    Tokens.screen: root.contentItem.Tokens.screen
                    text: Tr.trCtx("Cancel", "button")
                    type: TextButton.Text

                    onClicked: deleteDialog.close()
                }
                TextButton {
                    Tokens.screen: root.contentItem.Tokens.screen
                    disabled: root.working || root.connected
                    objectName: "vpnConfirmDeleteButton"
                    text: Tr.tr("Delete profile")

                    onClicked: {
                        if (root.deleteTarget)
                            ManagedVPN.run("delete", {
                                id: root.deleteTarget.id
                            });
                        deleteDialog.close();
                    }
                }
            }
        }
    }

    component Choice: ComboBox {
        font: root.contentItem.Tokens.font.body.small
        implicitHeight: 44 * root.contentItem.Tokens.scale
        palette.base: Colours.palette.m3surfaceContainer
        palette.buttonText: Colours.palette.m3onSurface
        palette.highlight: Colours.palette.m3primaryContainer
        palette.highlightedText: Colours.palette.m3onPrimaryContainer
        palette.text: Colours.palette.m3onSurface
        palette.window: Colours.palette.m3surfaceContainer

        background: StyledRect {
            color: Colours.palette.m3surfaceContainer
            radius: root.contentItem.Tokens.rounding.small
        }
    }
}
