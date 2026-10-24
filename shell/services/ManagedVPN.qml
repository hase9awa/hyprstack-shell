pragma Singleton

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Hyprstack
import Hyprstack.I18n

Singleton {
    id: root

    property var data: ({ profiles: [], groups: [], routes: [], selectedProfile: -1, mode: "tun" })
    readonly property var profiles: data.profiles ?? []
    readonly property var routes: data.routes ?? []
    readonly property bool busy: mutation.running
    property string action
    property string error
    property string payload
    property bool refreshPending
    property var window: null
    property var windowComponent: null

    signal operationFinished(command: string, success: bool)

    function refresh(): void {
        if (read.running) {
            refreshPending = true;
            return;
        }
        read.running = true;
    }

    function run(command: string, value: var): void {
        if (busy)
            return;
        action = command;
        error = "";
        payload = JSON.stringify(value ?? {});
        mutation.stdinEnabled = true;
        mutation.command = ["python3", `${Quickshell.shellDir}/assets/vpn.py`, command];
        mutation.running = true;
    }

    function openSettings(): void {
        if (window) {
            window.visible = true;
            window.contentItem.Window.window?.requestActivate();
        } else {
            if (!windowComponent)
                windowComponent = Qt.createComponent(Qt.resolvedUrl("../modules/vpn/VpnWindow.qml"));
            if (windowComponent.status === Component.Ready) {
                window = windowComponent.createObject(root);
            } else {
                Toaster.toast(Tr.tr("VPN"), windowComponent.errorString(), "vpn_key_alert");
            }
        }
        refresh();
    }

    Component.onCompleted: refresh()

    Process {
        id: read
        command: ["python3", `${Quickshell.shellDir}/assets/vpn.py`, "overview"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const value = JSON.parse(text);
                    if (value.error) {
                        root.error = Tr.tr(value.error);
                        root.data = Object.assign({}, root.data, {installed: value.installed !== false});
                    } else
                        root.data = value;
                } catch (err) {
                    root.error = Tr.tr("Unable to read VPN status");
                }
            }
        }
        onExited: {
            if (root.refreshPending) {
                root.refreshPending = false;
                Qt.callLater(root.refresh);
            }
        }
    }

    Process {
        id: mutation
        onStarted: {
            mutation.write(root.payload);
            mutation.stdinEnabled = false;
            root.payload = "";
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const value = JSON.parse(text);
                    if (value.error) {
                        root.error = Tr.tr(value.error);
                        Toaster.toast(Tr.tr("VPN"), root.error, "vpn_key_alert");
                    }
                } catch (err) {
                    root.error = Tr.tr("The VPN action did not complete");
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            Qt.callLater(() => {
                root.refresh();
                VPN.checkStatus();
                root.operationFinished(root.action, exitCode === 0 && root.error.length === 0);
            });
        }
    }

    Timer {
        interval: 3000
        running: root.window?.visible ?? false
        repeat: true
        onTriggered: if (!root.busy) root.refresh()
    }
}
