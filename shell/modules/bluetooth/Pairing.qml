pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack.Config
import Hyprstack.Services
import qs.services

// The questions bluez asks while a device pairs. Nothing else in the session
// answers them, and bluez refuses a pairing it cannot ask about, so the shell
// keeps an agent and puts each question on the screen.
Scope {
    id: root

    readonly property bool registered: agentLoader.item?.registered ?? false
    readonly property int pending: agentLoader.item?.pending ?? 0

    // A nested compositor shares the system bus with the desktop that started
    // it and must not take the pairing questions away from the real shell.
    LazyLoader {
        id: agentLoader

        active: Quickshell.env("HYPRSTACK_NESTED") !== "1" && GlobalConfig.services.bluetoothAgent

        Scope {
            id: agentScope

            readonly property bool registered: agent.registered
            readonly property int pending: agent.requests.length

            BluezAgent {
                id: agent
            }

            Instantiator {
                model: ScriptModel {
                    values: [...agent.requests]
                }

                PairDialog {
                    required property BluezRequest modelData

                    request: modelData
                    // Evaluated while the dialog is being built, before it
                    // takes a surface, so it never shows up on the wrong
                    // monitor.
                    screen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Quickshell.screens[0]

                    // A prompt that has to be answered deserves a clear screen.
                    Component.onCompleted: {
                        Overview.close(false);
                        WindowSwitcher.close();
                        ShellState.closeDrawers();
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "bluez"

        function status(): string {
            return JSON.stringify({registered: root.registered, pending: root.pending});
        }
    }
}
