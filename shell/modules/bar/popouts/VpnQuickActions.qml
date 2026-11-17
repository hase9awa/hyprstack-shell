pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.services
import "../../../utils/scripts/vpn-location.js" as Location

Item {
    id: root
    objectName: "vpnQuickActions"

    required property PopoutState popouts
    readonly property bool managed: !VPN.selected || VPN.active.name === "native"
    readonly property bool connected: VPN.connected
    readonly property bool busy: VPN.connecting || VPN.disconnecting || (managed && ManagedVPN.busy)
    readonly property var profiles: managed ? ManagedVPN.profiles : []

    implicitWidth: 300 * Tokens.scale
    implicitHeight: layout.implicitHeight

    Component.onCompleted: if (managed) { ManagedVPN.refresh(); ManagedVPN.refreshLocations(); }

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.small

        StyledText {
            text: Tr.tr("VPN")
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
        }

        StyledText {
            Layout.fillWidth: true
            text: root.busy ? Tr.tr("Updating connection…")
                : root.connected ? Tr.tr("VPN connected") : Tr.tr("VPN disconnected")
            color: root.connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }

        StyledText {
            Layout.fillWidth: true
            text: root.managed ? (ManagedVPN.selectedProfile?.name ?? Tr.tr("No profiles configured"))
                : VPN.active.displayName
            maximumLineCount: 2
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            elide: Text.ElideRight
        }

        IconTextButton {
            objectName: "vpnQuickToggle"
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            disabled: root.busy
            icon: root.connected ? "link_off" : "vpn_key"
            text: root.connected ? Tr.tr("Disconnect") : Tr.tr("Connect")
            onClicked: {
                if (root.connected) VPN.disconnect();
                else if (root.managed) ManagedVPN.connectSelected();
                else VPN.connect();
            }
        }

        ListView {
            id: profileList
            objectName: "vpnQuickProfiles"
            Layout.fillWidth: true
            visible: root.profiles.length > 0
            implicitHeight: Math.max(0, Math.min(contentHeight, 280 * Tokens.scale))
            model: root.profiles
            clip: true
            spacing: Tokens.spacing.extraSmall
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: StyledScrollBar { flickable: profileList }

            delegate: StyledRadioButton {
                id: profileRow
                required property var modelData
                readonly property var located: Object.assign({}, modelData,
                    {country: ManagedVPN.locationCodes[modelData.id] || modelData.country || ""})
                objectName: "vpnQuickProfile_" + modelData.id
                width: profileList.width
                implicitHeight: 36 * Tokens.scale
                enabled: !root.busy
                text: Location.label(modelData)
                checked: ManagedVPN.data.selectedProfile === modelData.id
                onClicked: if (!root.busy && ManagedVPN.data.selectedProfile !== modelData.id)
                    ManagedVPN.run("select", {id: modelData.id})

                contentItem: RowLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: profileRow.indicator.right
                    anchors.right: parent.right
                    anchors.leftMargin: Tokens.spacing.medium
                    spacing: Tokens.spacing.small
                    StyledText {
                        objectName: "vpnQuickFlag_" + profileRow.modelData.id
                        text: Location.flag(profileRow.located)
                        font.pixelSize: 20 * Tokens.scale
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: profileRow.text
                        elide: Text.ElideRight
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.managed ? ManagedVPN.error : VPN.status.reason ?? ""
            color: Colours.palette.m3error
            font: Tokens.font.body.small
            maximumLineCount: 2
            elide: Text.ElideRight
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }

        IconTextButton {
            objectName: "vpnQuickSettings"
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            inactiveColour: Colours.palette.m3primaryContainer
            inactiveOnColour: Colours.palette.m3onPrimaryContainer
            verticalPadding: Tokens.padding.extraSmall
            text: Tr.tr("Open settings")
            icon: "settings"
            onClicked: {
                root.popouts.hasCurrent = false;
                ManagedVPN.openSettings();
            }
        }
    }
}
