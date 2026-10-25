pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Bluetooth
import Hyprstack.Components
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus
import qs.modules.bar.popouts as BarPopouts

StyledRect {
    id: root

    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts

    readonly property var quickToggles: {
        const seenIds = new Set();

        return Config.utilities.quickToggles.values.filter(item => {
            if (!item.enabled)
                return false;

            if (seenIds.has(item.id)) {
                return false;
            }

            seenIds.add(item.id);
            return true;
        });
    }
    readonly property int columns: Math.max(1, Math.min(4, quickToggles.length,
        Math.floor((width - Tokens.padding.large * 2 + Tokens.spacing.small) / (64 * Tokens.scale + Tokens.spacing.small))))
    readonly property real tileWidth: Math.max(0, Math.floor((width - Tokens.padding.large * 2 - Tokens.spacing.small * (columns - 1)) / columns))

    implicitHeight: layout.implicitHeight + layout.anchors.margins * 2

    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: Tr.tr("Quick toggles")
            font: Tokens.font.body.medium
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: Math.ceil(root.quickToggles.length / root.columns)

            QuickToggleRow {
                required property int index

                model: root.quickToggles.slice(index * root.columns, (index + 1) * root.columns)
            }
        }
    }

    component QuickToggleRow: ButtonRow {
        property alias model: repeater.model

        Layout.alignment: Qt.AlignHCenter
        spacing: Tokens.spacing.small

        Repeater {
            id: repeater

            delegate: DelegateChooser {
                role: "id"

                DelegateChoice {
                    roleValue: "wifi"
                    delegate: Toggle {
                        icon: "wifi"
                        caption: Tr.tr("Wi-Fi")
                        checked: Nmcli.wifiEnabled
                        onClicked: Nmcli.toggleWifi()
                    }
                }
                DelegateChoice {
                    roleValue: "bluetooth"
                    delegate: Toggle {
                        icon: "bluetooth"
                        caption: Tr.tr("Bluetooth")
                        checked: Bluetooth.defaultAdapter?.enabled ?? false // qmllint disable unresolved-type
                        onClicked: {
                            const adapter = Bluetooth.defaultAdapter; // qmllint disable unresolved-type
                            if (adapter)
                                adapter.enabled = !adapter.enabled;
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "mic"
                    delegate: Toggle {
                        icon: "mic"
                        caption: Tr.tr("Microphone")
                        checked: !Audio.sourceMuted
                        onClicked: {
                            const audio = Audio.source?.audio;
                            if (audio)
                                audio.muted = !audio.muted;
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "settings"
                    delegate: Toggle {
                        icon: "settings"
                        caption: Tr.tr("Settings")
                        inactiveOnColour: Colours.palette.m3onSurfaceVariant
                        isToggle: false
                        onClicked: {
                            root.screenState.utilities = false;
                            WindowFactory.create();
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "gameMode"
                    delegate: Toggle {
                        icon: "gamepad"
                        caption: Tr.tr("Game mode")
                        checked: GameMode.enabled
                        onClicked: GameMode.enabled = !GameMode.enabled
                    }
                }
                DelegateChoice {
                    roleValue: "dnd"
                    delegate: Toggle {
                        icon: "notifications_off"
                        caption: Tr.tr("Do not disturb")
                        checked: Notifs.dnd
                        onClicked: Notifs.dnd = !Notifs.dnd
                    }
                }
                DelegateChoice {
                    roleValue: "vpn"
                    delegate: Toggle {
                        objectName: "utilitiesVpnToggle"
                        icon: "shield_lock"
                        caption: Tr.tr("VPN")
                        showCaption: true
                        checked: VPN.connected && VPN.status.state !== "needs-auth" && VPN.status.state !== "error"
                        disabled: VPN.connecting || VPN.disconnecting || (VPN.active.name === "native" && ManagedVPN.busy)
                        isToggle: VPN.status.state !== "needs-auth" && VPN.status.state !== "error"
                        inactiveOnColour: Colours.palette.m3onSurfaceVariant
                        onClicked: {
                            if (VPN.active.name === "native" && ManagedVPN.profiles.length === 0)
                                ManagedVPN.openSettings();
                            else
                                VPN.toggle();
                        }
                    }
                }
            }
        }
    }

    component Toggle: IconButton {
        id: button

        required property string caption
        property bool showCaption: false

        objectName: `quickToggle_${icon}`
        implicitWidth: root.tileWidth
        label.visible: !showCaption
        inactiveColour: Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)
        fillWidth: false
        isToggle: true
        isRound: true

        ToolTip.visible: hovered
        ToolTip.text: caption
        ToolTip.delay: 400

        Row {
            visible: button.showCaption

            anchors.centerIn: parent
            anchors.verticalCenterOffset: 1
            spacing: Tokens.spacing.extraSmall

            MaterialIcon {
                text: button.icon
                fontStyle: button.font
                color: button.onColour
                fill: !button.isToggle || button.internalChecked ? 1 : 0
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: button.caption
                font: Tokens.font.label.builders.small.weight(Font.DemiBold).build()
                color: button.onColour
            }
        }
    }
}
