pragma ComponentBehavior: Bound

import "./kblayout"
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Hyprstack.Config
import qs.components
import qs.services

Item {
    id: root

    required property PopoutState popouts
    readonly property Popout currentPopout: content.children.find(c => c.shouldBeActive) ?? null
    readonly property Item current: currentPopout?.item ?? null

    readonly property bool flowing: GlobalConfig.appearance.anim.shellPreset==="goop"
        && GlobalConfig.appearance.anim.durations.scale>0 && !GameMode.enabled
    property size readySize: Qt.size(0,0)
    function captureSize(): void {
        const p=currentPopout;
        if(!p?.item || !p.ready || p.implicitWidth<=0 || p.implicitHeight<=0) return;
        readySize=Qt.size(p.implicitWidth+Tokens.padding.large*2,p.implicitHeight+Tokens.padding.large*2);
    }
    onCurrentPopoutChanged: Qt.callLater(captureSize)
    Connections {
        target: root.currentPopout
        function onImplicitWidthChanged(): void {Qt.callLater(root.captureSize);}
        function onImplicitHeightChanged(): void {Qt.callLater(root.captureSize);}
        function onReadyChanged(): void {Qt.callLater(root.captureSize);}
        function onItemChanged(): void {Qt.callLater(root.captureSize);}
    }
    implicitWidth: flowing ? readySize.width : currentPopout ? currentPopout.implicitWidth+Tokens.padding.large*2 : 0
    implicitHeight: flowing ? readySize.height : currentPopout ? currentPopout.implicitHeight+Tokens.padding.large*2 : 0

    Item {
        id: content

        anchors.fill: parent
        anchors.margins: Tokens.padding.large

        Popout {
            name: "activewindow"
            sourceComponent: ActiveWindow {
                popouts: root.popouts
            }
        }

        Popout {
            name: "tasks"
            sourceComponent: TaskPreview {
                popouts: root.popouts
            }
        }

        Popout {
            id: networkPopout

            name: "network"
            sourceComponent: Network {
                popouts: root.popouts
                view: Nmcli.activeEthernet ? "ethernet" : "wireless"
            }
        }

        Popout {
            id: passwordPopout

            name: "wirelesspassword"
            sourceComponent: WirelessPassword {
                id: passwordComponent

                popouts: root.popouts
                network: (networkPopout.item as Network)?.passwordNetwork ?? null
            }

            Connections {
                function onCurrentNameChanged() {
                    // Update network immediately when password popout becomes active
                    if (root.popouts.currentName === "wirelesspassword") {
                        // Set network immediately if available
                        if ((networkPopout.item as Network)?.passwordNetwork) {
                            if (passwordPopout.item) {
                                (passwordPopout.item as WirelessPassword).network = (networkPopout.item as Network).passwordNetwork;
                            }
                        }
                        // Also try after a short delay in case networkPopout.item wasn't ready
                        Qt.callLater(() => {
                            if (passwordPopout.item && (networkPopout.item as Network)?.passwordNetwork) {
                                (passwordPopout.item as WirelessPassword).network = (networkPopout.item as Network).passwordNetwork;
                            }
                        }, 100);
                    }
                }

                target: root.popouts
            }

            Connections {
                function onItemChanged() {
                    // When network popout loads, update password popout if it's active
                    if (root.popouts.currentName === "wirelesspassword" && passwordPopout.item) {
                        Qt.callLater(() => {
                            if ((networkPopout.item as Network)?.passwordNetwork) {
                                (passwordPopout.item as WirelessPassword).network = (networkPopout.item as Network).passwordNetwork;
                            }
                        });
                    }
                }

                target: networkPopout
            }
        }

        Popout {
            name: "bluetooth"
            sourceComponent: Bluetooth {
                popouts: root.popouts
            }
        }

        Popout {
            name: "vpn"
            sourceComponent: VpnQuickActions {
                popouts: root.popouts
            }
        }

        Popout {
            name: "notifications"
            sourceComponent: NotificationQuickActions {
                popouts: root.popouts
            }
        }

        Popout {
            name: "battery"
            sourceComponent: Battery {}
        }

        Popout {
            name: "audio"
            sourceComponent: AudioPopout {
                popouts: root.popouts
            }
        }

        Popout {
            name: "kblayout"
            sourceComponent: KbLayout {}
        }

        Popout {
            name: "lockstatus"
            sourceComponent: LockStatus {}
        }

        Popout {
            name: root.flowing ? "traymenu" : "goopTrayInactive"
            ready: item?.populated ?? false
            sourceComponent: TrayMenu {
                popouts: root.popouts
                trayItem: root.popouts.trayItem?.menu ?? null
            }
        }

        Repeater {
            model: root.flowing ? [] : SystemTray.items

            Popout {
                id: trayPopout
                required property int index
                required property var modelData

                name: `traymenu${index}`
                sourceComponent: TrayMenu {
                    popouts: root.popouts
                    trayItem: trayPopout.modelData.menu
                }
            }
        }
    }

    component Popout: Loader {
        id: popout

        required property string name
        readonly property bool shouldBeActive: root.popouts.currentName === name
        property bool ready: true

        anchors.centerIn: parent

        opacity: 0
        active: false

        PopoutContentReveal {
            target: popout.item
            active: root.flowing && popout.shouldBeActive && popout.name !== "network" && popout.name !== "tasks"
            revision: popout.name === "traymenu" ? root.popouts.trayRevision : 0
        }

        states: State {
            name: "active"
            when: popout.shouldBeActive

            PropertyChanges {
                popout.active: true
                popout.opacity: 1
            }
        }

        transitions: [
            Transition {
                from: "active"
                to: ""

                SequentialAnimation {
                    Anim {
                        property: "opacity"
                        type: Anim.DefaultEffects
                        duration: popout.name === "tasks" ? 0 : popout.Tokens.anim.durations.expressiveDefaultEffects
                    }
                    PropertyAction {
                        property: "active"
                    }
                }
            },
            Transition {
                from: ""
                to: "active"

                SequentialAnimation {
                    PropertyAction {
                        property: "active"
                    }
                    Anim {
                        property: "opacity"
                        type: Anim.SlowEffects
                        duration: popout.name === "tasks" ? 0 : popout.Tokens.anim.durations.expressiveSlowEffects
                    }
                }
            }
        ]
    }
}
