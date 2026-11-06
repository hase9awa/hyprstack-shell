pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack.Config
import Hyprstack.Services
import qs.services

// The passwords NetworkManager asks its agents for. The shell's own Wi-Fi
// prompt never reaches here, because those connections are started with the
// password already in hand; what does is everything else — a VPN, an
// enterprise network, a connection brought up on its own or from elsewhere.
Scope {
    id: root

    readonly property bool registered: agentLoader.item?.registered ?? false
    readonly property int pending: agentLoader.item?.pending ?? 0

    // A nested compositor shares the system bus with the desktop that started
    // it and must not answer for the real shell.
    LazyLoader {
        id: agentLoader

        active: Quickshell.env("HYPRSTACK_NESTED") !== "1" && GlobalConfig.services.networkSecrets

        Scope {
            id: agentScope

            readonly property bool registered: agent.registered
            readonly property int pending: agent.requests.length

            NmSecretAgent {
                id: agent
            }

            Instantiator {
                model: ScriptModel {
                    values: [...agent.requests]
                }

                SecretDialog {
                    required property SecretRequest modelData

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
        target: "nmsecrets"

        function status(): string {
            return JSON.stringify({registered: root.registered, pending: root.pending});
        }
    }
}
